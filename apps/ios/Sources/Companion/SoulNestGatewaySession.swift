import Foundation
import Observation

/// Per-turn events the session derives from raw Gateway events. The store
/// subscribes so each in-flight message can track its lifecycle status.
enum SoulNestRequestEvent: Equatable, Sendable {
    case started(requestID: String)
    case textUpdated(requestID: String)
    case completed(requestID: String)
    case failed(requestID: String, error: SoulNestGatewayError)
}

/// UI-facing state holder for the single SoulNest Gateway connection.
///
/// SwiftUI talks to this facade rather than a socket or pairing implementation.
/// The OpenClaw runtime adapter is injected through `SoulNestGatewayClient`.
///
/// The session owns the one active turn at a time: it tracks its request id and
/// session key, arms a stall timeout, cancels the underlying run on stop, and
/// ends the turn when the connection drops. A reconnect never replays
/// transcript; the store keeps the failed message and offers a retry.
@MainActor
@Observable
final class SoulNestGatewaySession {
    private let client: any SoulNestGatewayClient
    private let responseTimeout: Duration
    private var eventTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var activeRequest: (requestID: String, sessionKey: String)?
    private var cancellationPendingRequestID: String?

    private(set) var state: SoulNestGatewayConnectionState
    private(set) var lastError: SoulNestGatewayError?
    private(set) var isGenerating: Bool = false
    private(set) var assistantText: [String: String] = [:]

    let requestEvents: AsyncStream<SoulNestRequestEvent>
    private let requestEventsContinuation: AsyncStream<SoulNestRequestEvent>.Continuation

    init(
        client: any SoulNestGatewayClient,
        responseTimeout: Duration = .seconds(60))
    {
        self.client = client
        self.responseTimeout = responseTimeout
        self.state = client.state
        (self.requestEvents, self.requestEventsContinuation) = AsyncStream.makeStream(
            of: SoulNestRequestEvent.self)
        self.observeEvents()
    }

    isolated deinit {
        self.eventTask?.cancel()
        self.timeoutTask?.cancel()
    }

    func connect(to endpoint: SoulNestGatewayEndpoint) async {
        self.lastError = nil
        do {
            try await self.client.connect(to: endpoint)
            self.state = self.client.state
        } catch {
            let mapped = Self.map(error)
            self.lastError = mapped
            self.state = .failed(mapped)
        }
    }

    func disconnect() async {
        await self.client.disconnect()
        self.state = .disconnected
    }

    func cancelPairing() async {
        await self.client.cancelPairing()
        self.state = self.client.state
    }

    @discardableResult
    func sendText(_ text: String, sessionKey: String) async throws -> String {
        guard case .connected = self.state else {
            throw SoulNestGatewayError.notConnected
        }
        do {
            let runID = try await client.sendText(text, sessionKey: sessionKey)
            self.assistantText[runID] = ""
            self.isGenerating = true
            self.activeRequest = (requestID: runID, sessionKey: sessionKey)
            self.cancellationPendingRequestID = nil
            self.requestEventsContinuation.yield(.started(requestID: runID))
            self.armTimeout()
            return runID
        } catch {
            let mapped = Self.map(error)
            self.lastError = mapped
            throw mapped
        }
    }

    /// Stops the in-flight turn: cancels the underlying gateway run and marks
    /// the turn cancelled so the UI can offer a retry.
    ///
    /// The terminal `.cancelled` state is derived on the event loop rather than
    /// here so a partial snapshot the transport already delivered before the
    /// stop is consumed first. The gateway abort response itself can also carry
    /// the final partial; a settle timeout fails the turn if no echo arrives.
    func cancelCurrentRequest() async {
        guard let activeRequest else { return }
        self.cancelTimeout()
        let requestID = activeRequest.requestID
        let sessionKey = activeRequest.sessionKey
        self.cancellationPendingRequestID = requestID
        do {
            try await self.client.abortRun(sessionKey: sessionKey, runId: requestID)
            self.armCancellationSettle(requestID: requestID, error: .cancelled)
        } catch {
            self.armCancellationSettle(requestID: requestID, error: Self.map(error))
        }
    }

    private func observeEvents() {
        self.eventTask?.cancel()
        self.eventTask = Task { [weak self, client] in
            for await event in client.events {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                switch event {
                case let .connectionChanged(state):
                    self.handleConnectionChanged(state)
                case let .assistantText(requestID, text, isFinal):
                    self.handleAssistantText(requestID: requestID, text: text, isFinal: isFinal)
                case let .requestFailed(requestID, error):
                    self.handleRequestFailed(requestID: requestID, error: error)
                }
                self.settlePendingCancellation()
            }
        }
    }

    /// Fails the cancelled turn on the event loop once buffered events are
    /// consumed, so the partial snapshot delivered alongside the stop is
    /// reflected in the terminal state.
    private func settlePendingCancellation() {
        guard let pending = self.cancellationPendingRequestID,
              pending == self.activeRequest?.requestID
        else { return }
        self.fail(pending, error: .cancelled)
    }

    private func handleConnectionChanged(_ state: SoulNestGatewayConnectionState) {
        self.state = state
        if case let .failed(error) = state {
            self.lastError = error
        }
        // A dropped connection ends the in-flight turn. Partial text stays
        // visible; reconnect never replays transcript.
        if !state.isConnected, let activeRequest {
            self.fail(activeRequest.requestID, error: .networkUnavailable)
        }
    }

    private func handleAssistantText(requestID: String, text: String, isFinal: Bool) {
        guard !requestID.isEmpty, requestID == self.activeRequest?.requestID else { return }
        if isFinal {
            if !text.isEmpty {
                self.assistantText[requestID] = text
            }
            self.finish(requestID)
            self.requestEventsContinuation.yield(.completed(requestID: requestID))
            return
        }
        if !text.isEmpty {
            self.assistantText[requestID] = text
            self.requestEventsContinuation.yield(.textUpdated(requestID: requestID))
            // Streaming activity resets the stall timeout.
            self.armTimeout()
        }
        self.isGenerating = true
    }

    private func handleRequestFailed(requestID: String?, error: SoulNestGatewayError) {
        if let requestID {
            guard requestID == self.activeRequest?.requestID else { return }
            self.fail(requestID, error: error)
        } else if let activeRequest {
            // A failure without a request id refers to the active turn.
            self.fail(activeRequest.requestID, error: error)
        }
    }

    private func finish(_ requestID: String) {
        guard self.activeRequest?.requestID == requestID else { return }
        self.cancellationPendingRequestID = nil
        self.activeRequest = nil
        self.cancelTimeout()
        self.isGenerating = false
    }

    private func fail(_ requestID: String, error: SoulNestGatewayError) {
        guard self.activeRequest?.requestID == requestID else { return }
        self.cancellationPendingRequestID = nil
        self.activeRequest = nil
        self.cancelTimeout()
        self.lastError = error
        self.isGenerating = false
        self.requestEventsContinuation.yield(.failed(requestID: requestID, error: error))
    }

    /// Arms a stall timeout: the turn ends as a retryable failure when no
    /// terminal event and no new snapshot arrives within the window.
    private func armTimeout() {
        guard self.responseTimeout > .zero, let activeRequest else { return }
        self.timeoutTask?.cancel()
        let timeout = self.responseTimeout
        let requestID = activeRequest.requestID
        let sessionKey = activeRequest.sessionKey
        self.timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self, !Task.isCancelled,
                  self.activeRequest?.requestID == requestID
            else { return }
            try? await self.client.abortRun(sessionKey: sessionKey, runId: requestID)
            self.fail(requestID, error: .requestTimedOut)
        }
    }

    private func cancelTimeout() {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
    }

    /// Fail-safe for cancellation: if the transport never echoes the abort
    /// (no event arrives to settle the turn), the turn still ends with the
    /// given error.
    private func armCancellationSettle(requestID: String, error: SoulNestGatewayError) {
        self.timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard let self, !Task.isCancelled,
                  self.activeRequest?.requestID == requestID
            else { return }
            self.fail(requestID, error: error)
        }
    }

    static func map(_ error: any Error) -> SoulNestGatewayError {
        if let gatewayError = error as? SoulNestGatewayError {
            return gatewayError
        }
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return .networkUnavailable
            case NSURLErrorTimedOut:
                return .requestTimedOut
            case NSURLErrorCancelled:
                return .cancelled
            default:
                return .gatewayUnavailable
            }
        }
        return .unknown(error.localizedDescription)
    }
}
