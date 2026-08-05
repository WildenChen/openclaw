import Foundation
@testable import OpenClaw

/// Shared test mock for `SoulNestGatewayClient`. Provides fine-grained control
/// over connection state and event emission so store/session tests can drive
/// the full streaming lifecycle.
@MainActor
final class MockSoulNestGatewayClient: SoulNestGatewayClient {
    struct SentText: Equatable {
        let text: String
        let sessionKey: String
    }

    var state: SoulNestGatewayConnectionState = .disconnected
    var connectError: SoulNestGatewayError?
    var connectedEndpoint: SoulNestGatewayEndpoint?
    var sentTexts: [SentText] = []
    var disconnectCount = 0
    var sendShouldFail = false
    var sendFailError: SoulNestGatewayError? = .gatewayUnavailable

    private let continuation: AsyncStream<SoulNestGatewayEvent>.Continuation
    let events: AsyncStream<SoulNestGatewayEvent>

    init() {
        var continuation: AsyncStream<SoulNestGatewayEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func connect(to endpoint: SoulNestGatewayEndpoint) async throws {
        if let connectError {
            self.state = .failed(connectError)
            throw connectError
        }
        self.connectedEndpoint = endpoint
        self.state = .connected
        self.continuation.yield(.connectionChanged(.connected))
    }

    func disconnect() async {
        self.disconnectCount += 1
        self.state = .disconnected
        self.continuation.yield(.connectionChanged(.disconnected))
    }

    func cancelPairing() async {
        self.state = .disconnected
        self.continuation.yield(.connectionChanged(.disconnected))
    }

    func sendText(_ text: String, sessionKey: String) async throws -> String {
        if self.sendShouldFail {
            throw self.sendFailError ?? .gatewayUnavailable
        }
        self.sentTexts.append(.init(text: text, sessionKey: sessionKey))
        return "request-\(self.sentTexts.count)"
    }

    func emitText(requestID: String, text: String, isFinal: Bool = false) {
        self.continuation.yield(
            .assistantText(requestID: requestID, text: text, isFinal: isFinal))
    }

    func emitFailure(requestID: String?, error: SoulNestGatewayError) {
        self.continuation.yield(.requestFailed(requestID: requestID, error: error))
    }
}
