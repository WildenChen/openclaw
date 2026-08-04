import Foundation
import XCTest
@testable import OpenClaw

@MainActor
final class SoulNestGatewaySessionTests: XCTestCase {
    func testEndpointRejectsUnsupportedURL() throws {
        XCTAssertThrowsError(try SoulNestGatewayEndpoint(
            url: XCTUnwrap(URL(string: "file:///tmp/gateway"))))
        { error in
            XCTAssertEqual(error as? SoulNestGatewayError, .invalidEndpoint)
        }
    }

    func testConnectAndSendUseInjectedGatewayClient() async throws {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let endpoint = try SoulNestGatewayEndpoint(url: XCTUnwrap(URL(string: "wss://gateway.example.test")))

        await session.connect(to: endpoint)
        let requestID = try await session.sendText("你好", sessionKey: "agent:yujie:soulnest-ios-test")

        XCTAssertEqual(session.state, .connected)
        XCTAssertEqual(client.connectedEndpoint, endpoint)
        XCTAssertEqual(client.sentTexts, [
            .init(text: "你好", sessionKey: "agent:yujie:soulnest-ios-test"),
        ])
        XCTAssertEqual(requestID, "request-1")
    }

    func testAuthenticationFailureIsClassifiedForUI() async throws {
        let client = MockSoulNestGatewayClient()
        client.connectError = .authenticationFailed
        let session = SoulNestGatewaySession(client: client)
        let endpoint = try SoulNestGatewayEndpoint(url: XCTUnwrap(URL(string: "wss://gateway.example.test")))

        await session.connect(to: endpoint)

        XCTAssertEqual(session.state, .failed(.authenticationFailed))
        XCTAssertEqual(session.lastError, .authenticationFailed)
    }

    func testSendRequiresConnection() async throws {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)

        do {
            _ = try await session.sendText("你好", sessionKey: "session")
            XCTFail("Expected notConnected")
        } catch {
            XCTAssertEqual(error as? SoulNestGatewayError, .notConnected)
        }
    }

    func testConversationIDResolvesSessionKeyThroughMergedMapping() async throws {
        let suiteName = "SoulNestGatewaySessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SoulNestConversationSessionStore(defaults: defaults)
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let endpoint = try SoulNestGatewayEndpoint(url: XCTUnwrap(URL(string: "wss://gateway.example.test")))

        await session.connect(to: endpoint)
        let mapping = store.session(for: UUID())
        _ = try await session.sendText("你好", sessionKey: mapping.sessionKey)

        XCTAssertEqual(client.sentTexts.map(\.sessionKey), [mapping.sessionKey])
        XCTAssertEqual(SessionKey.agentId(from: mapping.sessionKey), "yujie")
    }

    func testDisconnectDoesNotExposeTransportDetails() async throws {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let endpoint = try SoulNestGatewayEndpoint(url: XCTUnwrap(URL(string: "https://gateway.example.test")))
        await session.connect(to: endpoint)

        await session.disconnect()

        XCTAssertEqual(session.state, .disconnected)
        XCTAssertEqual(client.disconnectCount, 1)
    }
}

@MainActor
private final class MockSoulNestGatewayClient: SoulNestGatewayClient {
    struct SentText: Equatable {
        let text: String
        let sessionKey: String
    }

    var state: SoulNestGatewayConnectionState = .disconnected
    var connectError: SoulNestGatewayError?
    var connectedEndpoint: SoulNestGatewayEndpoint?
    var sentTexts: [SentText] = []
    var disconnectCount = 0

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
        self.sentTexts.append(.init(text: text, sessionKey: sessionKey))
        return "request-\(self.sentTexts.count)"
    }
}
