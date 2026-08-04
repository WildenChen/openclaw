import Foundation
import Observation

/// UI-facing state holder for the single SoulNest Gateway connection.
///
/// SwiftUI talks to this facade rather than a socket or pairing implementation.
/// The OpenClaw runtime adapter is injected through `SoulNestGatewayClient`.
@MainActor
@Observable
final class SoulNestGatewaySession {
    private let client: any SoulNestGatewayClient
    private var eventTask: Task<Void, Never>?

    private(set) var state: SoulNestGatewayConnectionState
    private(set) var lastError: SoulNestGatewayError?
    private(set) var isGenerating: Bool = false
    private(set) var assistantText: [String: String] = [:]

    init(client: any SoulNestGatewayClient) {
        self.client = client
        self.state = client.state
        self.observeEvents()
    }

    isolated deinit {
        self.eventTask?.cancel()
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
            let runID = try await self.client.sendText(text, sessionKey: sessionKey)
            self.assistantText[runID] = ""
            self.isGenerating = true
            return runID
        } catch {
            let mapped = Self.map(error)
            self.lastError = mapped
            throw mapped
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
                    self.state = state
                    if case let .failed(error) = state {
                        self.lastError = error
                    }
                case let .assistantText(requestID, text, isFinal):
                    if isFinal {
                        self.isGenerating = false
                    } else {
                        self.isGenerating = true
                        self.assistantText[requestID, default: ""] += text
                    }
                case let .requestFailed(_, error):
                    self.isGenerating = false
                    self.lastError = error
                }
            }
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
