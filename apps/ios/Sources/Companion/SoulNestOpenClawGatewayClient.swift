import Foundation
import OpenClawChatUI
import OpenClawKit

/// Connection surface the production client adapts.
///
/// Kept as a narrow protocol so the client can be tested with a stub instead
/// of a live `NodeAppModel`/`GatewayConnectionController`.
@MainActor
protocol SoulNestGatewayConnection: AnyObject {
    var state: SoulNestGatewayConnectionState { get }
    /// Fires after every connection-state change. The client forwards each
    /// firing as `SoulNestGatewayEvent.connectionChanged`.
    var changes: AsyncStream<Void> { get }

    func connect(to endpoint: SoulNestGatewayEndpoint) async
    func disconnect() async
    func cancelPairing() async
}

/// Production `SoulNestGatewayClient`: adapts the existing OpenClaw Gateway
/// runtime (operator session + connection controller) to the Companion
/// boundary. No second WebSocket, no local transcript, no provider fallback.
@MainActor
final class SoulNestOpenClawGatewayClient: SoulNestGatewayClient {
    private let connection: any SoulNestGatewayConnection
    private let transportProvider: @MainActor () -> any OpenClawChatTransport
    private let eventContinuation: AsyncStream<SoulNestGatewayEvent>.Continuation
    let events: AsyncStream<SoulNestGatewayEvent>
    private var connectionObserverTask: Task<Void, Never>?
    private var chatObserverTask: Task<Void, Never>?
    private var chatSubscriptionID = UUID()

    var state: SoulNestGatewayConnectionState {
        self.connection.state
    }

    init(
        connection: any SoulNestGatewayConnection,
        transportProvider: @escaping @MainActor () -> any OpenClawChatTransport)
    {
        self.connection = connection
        self.transportProvider = transportProvider
        (self.events, self.eventContinuation) = AsyncStream.makeStream(
            of: SoulNestGatewayEvent.self)
        self.observeConnectionChanges()
        if case .connected = connection.state {
            self.observeChatEvents()
        }
    }

    deinit {
        self.connectionObserverTask?.cancel()
        self.chatObserverTask?.cancel()
    }

    func connect(to endpoint: SoulNestGatewayEndpoint) async throws {
        await self.connection.connect(to: endpoint)
        if case let .failed(error) = self.connection.state {
            throw error
        }
    }

    func disconnect() async {
        await self.connection.disconnect()
    }

    func cancelPairing() async {
        await self.connection.cancelPairing()
    }

    @discardableResult
    func sendText(_ text: String, sessionKey: String) async throws -> String {
        guard case .connected = self.connection.state else {
            throw SoulNestGatewayError.notConnected
        }
        let transport = self.transportProvider()
        do {
            let response = try await transport.sendMessage(
                sessionKey: sessionKey,
                message: text,
                thinking: "",
                idempotencyKey: UUID().uuidString,
                attachments: [])
            return response.runId
        } catch {
            let mapped = SoulNestGatewaySession.map(error)
            self.eventContinuation.yield(.requestFailed(requestID: nil, error: mapped))
            throw mapped
        }
    }

    private func observeConnectionChanges() {
        self.connectionObserverTask?.cancel()
        let connection = self.connection
        self.connectionObserverTask = Task { [weak self] in
            for await _ in connection.changes {
                guard let self, !Task.isCancelled else { return }
                if case .connected = connection.state {
                    self.observeChatEvents()
                }
                self.eventContinuation.yield(.connectionChanged(connection.state))
            }
        }
    }

    /// Subscribes to chat events over the current operator session. The stream
    /// ends when the socket drops, so a fresh subscription is re-armed on every
    /// connected transition. The ID guard lets a stale subscription bail when a
    /// newer one is armed after it started iterating.
    private func observeChatEvents() {
        self.chatObserverTask?.cancel()
        self.chatSubscriptionID = UUID()
        let subscriptionID = self.chatSubscriptionID
        let transport = self.transportProvider()
        self.chatObserverTask = Task { [weak self] in
            for await event in transport.events() {
                guard let self, !Task.isCancelled, self.chatSubscriptionID == subscriptionID else {
                    return
                }
                guard case let .chat(chat) = event else { continue }
                self.forward(chat)
            }
        }
    }

    private func forward(_ chat: OpenClawChatEventPayload) {
        if let text = OpenClawChatEventText.assistantText(from: chat) {
            self.eventContinuation.yield(.assistantText(
                requestID: chat.runId ?? "",
                text: text,
                isFinal: chat.state == "final"))
        }
        switch chat.state {
        case "error":
            self.eventContinuation.yield(.requestFailed(
                requestID: chat.runId,
                error: Self.mapChatError(chat)))
        case "aborted":
            self.eventContinuation.yield(.requestFailed(
                requestID: chat.runId,
                error: .cancelled))
        default:
            break
        }
    }

    private static func mapChatError(_ chat: OpenClawChatEventPayload) -> SoulNestGatewayError {
        let message = chat.errorMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !message.isEmpty {
            return .unknown(message)
        }
        return .gatewayUnavailable
    }
}

/// Production connection adapter: maps the single OpenClaw operator gateway
/// (shared `NodeAppModel` + `GatewayConnectionController`) onto the Companion
/// connection state machine.
@MainActor
final class SoulNestOpenClawGatewayConnection: SoulNestGatewayConnection {
    static let connectSettleTimeout: Duration = .seconds(25)

    private let appModel: NodeAppModel
    private let controller: GatewayConnectionController
    private let changesContinuation: AsyncStream<Void>.Continuation
    let changes: AsyncStream<Void>

    private(set) var state: SoulNestGatewayConnectionState
    private var episodeHasConnected: Bool
    private var episodeHasLost: Bool
    private var reconnectAttempt: Int

    init(appModel: NodeAppModel, controller: GatewayConnectionController) {
        self.appModel = appModel
        self.controller = controller
        (self.changes, self.changesContinuation) = AsyncStream.makeStream(of: Void.self)
        let snapshot = Self.mapState(
            appModel: appModel,
            episodeHasConnected: appModel.isOperatorGatewayConnected,
            episodeHasLost: false,
            reconnectAttempt: 0)
        self.state = snapshot.state
        self.episodeHasConnected = snapshot.episodeHasConnected
        self.episodeHasLost = snapshot.episodeHasLost
        self.reconnectAttempt = snapshot.reconnectAttempt
        self.observe()
    }

    func connect(to endpoint: SoulNestGatewayEndpoint) async {
        guard let parameters = Self.connectionParameters(from: endpoint) else {
            self.set(.failed(.invalidEndpoint))
            return
        }
        // A fresh user-initiated connect restarts episode bookkeeping.
        self.episodeHasConnected = false
        self.episodeHasLost = false
        self.reconnectAttempt = 0

        if let stableID = parameters.stableID,
           Self.matchesLastKnownGateway(stableID)
        {
            // The target endpoint already matches the saved gateway, so reconnect
            // to it with its stored credentials instead of entering them again.
            await self.controller.connectLastKnown()
        } else {
            await self.controller.connectManual(
                host: parameters.host,
                port: parameters.port,
                useTLS: parameters.useTLS,
                forceReconnect: true)
        }
        await self.waitForSettledState()
    }

    func disconnect() async {
        self.appModel.disconnectGateway()
    }

    func cancelPairing() async {
        // Stop waiting for approval. The base runtime has no split disconnect,
        // so a plain disconnect is the closest equivalent.
        self.appModel.disconnectGateway()
    }

    private func observe() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.appModel.isOperatorGatewayConnected
            _ = self.appModel.gatewayPairingPaused
            _ = self.appModel.gatewayAutoReconnectEnabled
            _ = self.appModel.activeGatewayConnectConfig
            _ = self.appModel.lastGatewayProblem
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.recomputeState()
                self.observe()
            }
        }
    }

    private func recomputeState() {
        let snapshot = Self.mapState(
            appModel: self.appModel,
            episodeHasConnected: self.episodeHasConnected,
            episodeHasLost: self.episodeHasLost,
            reconnectAttempt: self.reconnectAttempt)
        self.episodeHasConnected = snapshot.episodeHasConnected
        self.episodeHasLost = snapshot.episodeHasLost
        self.reconnectAttempt = snapshot.reconnectAttempt
        self.set(snapshot.state)
    }

    private func set(_ newState: SoulNestGatewayConnectionState) {
        guard newState != self.state else { return }
        self.state = newState
        self.changesContinuation.yield(())
    }

    private func waitForSettledState() async {
        let deadline = ContinuousClock().now.advanced(by: Self.connectSettleTimeout)
        while ContinuousClock().now < deadline {
            switch self.state {
            case .connected, .pairing, .failed, .disconnected:
                return
            case .connecting, .reconnecting:
                break
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private static func mapState(
        appModel: NodeAppModel,
        episodeHasConnected: Bool,
        episodeHasLost: Bool,
        reconnectAttempt: Int) -> (
        state: SoulNestGatewayConnectionState,
        episodeHasConnected: Bool,
        episodeHasLost: Bool,
        reconnectAttempt: Int)
    {
        if appModel.isOperatorGatewayConnected {
            return (.connected, true, false, 0)
        }
        if appModel.gatewayPairingPaused {
            return (.pairing, episodeHasConnected, episodeHasLost, reconnectAttempt)
        }
        if let problem = appModel.lastGatewayProblem,
           problem.pauseReconnect || !problem.retryable
        {
            return (.failed(self.mapError(from: problem)), false, false, 0)
        }
        let inProgress = appModel.gatewayAutoReconnectEnabled
            || appModel.activeGatewayConnectConfig != nil
        if inProgress {
            if episodeHasConnected, !episodeHasLost {
                return (
                    .reconnecting(attempt: reconnectAttempt + 1),
                    episodeHasConnected,
                    true,
                    reconnectAttempt + 1)
            }
            if episodeHasLost {
                return (
                    .reconnecting(attempt: reconnectAttempt),
                    episodeHasConnected,
                    true,
                    reconnectAttempt)
            }
            return (.connecting, false, false, 0)
        }
        return (.disconnected, false, false, 0)
    }

    static func mapError(
        from problem: GatewayConnectionProblem) -> SoulNestGatewayError
    {
        switch GatewayConnectionIssue.detect(problem: problem) {
        case .none:
            return .gatewayUnavailable
        case .tokenMissing, .unauthorized:
            return .authenticationFailed
        case .pairingRequired:
            return .pairingFailed
        case .network:
            return .networkUnavailable
        case let .unknown(message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .unknown(problem.message) : .unknown(trimmed)
        }
    }

    private static func matchesLastKnownGateway(_ stableID: String) -> Bool {
        guard let last = GatewaySettingsStore.loadLastGatewayConnection() else { return false }
        switch last {
        case let .manual(_, _, _, stored):
            return stored == stableID
        case let .discovered(stored, _):
            return stored == stableID
        }
    }

    static func connectionParameters(
        from endpoint: SoulNestGatewayEndpoint) -> ConnectionParameters?
    {
        guard let host = endpoint.url.host, !host.isEmpty else { return nil }
        let scheme = endpoint.url.scheme?.lowercased()
        let useTLS = scheme == "wss" || scheme == "https"
        // Port 0 delegates resolution to the runtime manual connect
        // (default 18789, or 443 for Tailscale hosts).
        let port = endpoint.url.port ?? 0
        return ConnectionParameters(
            host: host,
            port: port,
            useTLS: useTLS,
            stableID: endpoint.stableID)
    }

    struct ConnectionParameters: Equatable {
        let host: String
        let port: Int
        let useTLS: Bool
        let stableID: String?
    }
}
