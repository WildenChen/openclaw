import Foundation
import OpenClawKit
import os
import XCTest
@testable import OpenClaw
@testable import OpenClawChatUI

@MainActor
final class SoulNestOpenClawGatewayClientTests: XCTestCase {
    func testSendTextReturnsRunIDAndForwardsAssistantTextEvents() async throws {
        let connection = MockSoulNestGatewayConnection(state: .connected)
        let transport = FakeChatTransport()
        transport.eventsToEmit = [
            .chat(OpenClawChatEventPayload(
                runId: "run-1",
                sessionKey: "agent:yujie:soulnest-ios-test",
                state: "delta",
                message: AnyCodable([
                    "role": "assistant",
                    "content": [["type": "text", "text": "你好，"]],
                ]),
                errorMessage: nil)),
            .chat(OpenClawChatEventPayload(
                runId: "run-1",
                sessionKey: "agent:yujie:soulnest-ios-test",
                state: "final",
                message: AnyCodable([
                    "role": "assistant",
                    "content": [
                        ["type": "text", "text": "你好，我是 Yujie。"],
                    ],
                ]),
                errorMessage: nil)),
        ]
        let client = SoulNestOpenClawGatewayClient(connection: connection) { transport }
        let collector = EventCollector(stream: client.events)
        defer { collector.cancel() }

        let runID = try await client.sendText("嗨", sessionKey: "agent:yujie:soulnest-ios-test")

        XCTAssertEqual(runID, "run-1")
        XCTAssertEqual(transport.sendCalls, [
            .init(sessionKey: "agent:yujie:soulnest-ios-test", message: "嗨"),
        ])
        await self.waitUntil { collector.containsAssistantText(requestID: "run-1", isFinal: true) }
        XCTAssertTrue(collector.containsAssistantText(requestID: "run-1", isFinal: false))
        XCTAssertFalse(collector.containsRequestFailed())
    }

    func testSendTextThrowsWhenNotConnected() async throws {
        let connection = MockSoulNestGatewayConnection(state: .disconnected)
        let client = SoulNestOpenClawGatewayClient(connection: connection) { FakeChatTransport() }

        do {
            _ = try await client.sendText("嗨", sessionKey: "agent:yujie:soulnest-ios-test")
            XCTFail("Expected notConnected")
        } catch {
            XCTAssertEqual(error as? SoulNestGatewayError, .notConnected)
        }
    }

    func testSendTextMapsTransportFailureAndEmitsRequestFailed() async throws {
        let connection = MockSoulNestGatewayConnection(state: .connected)
        let transport = FakeChatTransport()
        transport.sendError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: nil)
        let client = SoulNestOpenClawGatewayClient(connection: connection) { transport }
        let collector = EventCollector(stream: client.events)
        defer { collector.cancel() }

        do {
            _ = try await client.sendText("嗨", sessionKey: "agent:yujie:soulnest-ios-test")
            XCTFail("Expected networkUnavailable")
        } catch {
            XCTAssertEqual(error as? SoulNestGatewayError, .networkUnavailable)
        }
        await self.waitUntil { collector.containsRequestFailed(error: .networkUnavailable) }
    }

    func testSendTextMapsRunErrorEventToRequestFailed() async {
        let connection = MockSoulNestGatewayConnection(state: .connected)
        let transport = FakeChatTransport()
        transport.eventsToEmit = [
            .chat(OpenClawChatEventPayload(
                runId: "run-7",
                sessionKey: "agent:yujie:soulnest-ios-test",
                state: "error",
                message: nil,
                errorMessage: "agent run failed")),
        ]
        let client = SoulNestOpenClawGatewayClient(connection: connection) { transport }
        let collector = EventCollector(stream: client.events)
        defer { collector.cancel() }

        await self.waitUntil { collector.containsRequestFailed(requestID: "run-7") }
    }

    func testAbortRunDelegatesToTransport() async throws {
        let connection = MockSoulNestGatewayConnection(state: .connected)
        let transport = FakeChatTransport()
        let client = SoulNestOpenClawGatewayClient(connection: connection) { transport }

        try await client.abortRun(
            sessionKey: "agent:yujie:soulnest-ios-test",
            runId: "run-1")

        XCTAssertEqual(transport.abortCalls, [
            .init(sessionKey: "agent:yujie:soulnest-ios-test", runId: "run-1"),
        ])
    }

    func testAbortRunMapsTransportFailureAndEmitsRequestFailed() async throws {
        let connection = MockSoulNestGatewayConnection(state: .connected)
        let transport = FakeChatTransport()
        transport.abortError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: nil)
        let client = SoulNestOpenClawGatewayClient(connection: connection) { transport }
        let collector = EventCollector(stream: client.events)
        defer { collector.cancel() }

        do {
            try await client.abortRun(
                sessionKey: "agent:yujie:soulnest-ios-test",
                runId: "run-1")
            XCTFail("Expected requestTimedOut")
        } catch {
            XCTAssertEqual(error as? SoulNestGatewayError, .requestTimedOut)
        }
        await self.waitUntil { collector.containsRequestFailed(requestID: "run-1", error: .requestTimedOut) }
    }

    func testAbortedChatEventForwardsPartialTextThenCancelled() async {
        let connection = MockSoulNestGatewayConnection(state: .connected)
        let transport = FakeChatTransport()
        transport.eventsToEmit = [
            .chat(OpenClawChatEventPayload(
                runId: "run-1",
                sessionKey: "agent:yujie:soulnest-ios-test",
                state: "aborted",
                message: AnyCodable([
                    "role": "assistant",
                    "content": [["type": "text", "text": "Partial reply"]],
                ]),
                errorMessage: nil)),
        ]
        let client = SoulNestOpenClawGatewayClient(connection: connection) { transport }
        let collector = EventCollector(stream: client.events)
        defer { collector.cancel() }

        await self.waitUntil {
            collector.containsAssistantText(requestID: "run-1", isFinal: false)
                && collector.containsRequestFailed(requestID: "run-1", error: .cancelled)
        }
    }

    func testBareFinalEventStillCompletesTheTurn() async {
        let connection = MockSoulNestGatewayConnection(state: .connected)
        let transport = FakeChatTransport()
        transport.eventsToEmit = [
            .chat(OpenClawChatEventPayload(
                runId: "run-1",
                sessionKey: "agent:yujie:soulnest-ios-test",
                state: "final",
                message: nil,
                errorMessage: nil)),
        ]
        let client = SoulNestOpenClawGatewayClient(connection: connection) { transport }
        let collector = EventCollector(stream: client.events)
        defer { collector.cancel() }

        await self.waitUntil { collector.containsAssistantText(requestID: "run-1", isFinal: true) }
        XCTAssertFalse(collector.containsRequestFailed())
    }

    func testConnectDelegatesAndThrowsMappedFailure() async throws {
        let connection = MockSoulNestGatewayConnection()
        connection.connectError = .authenticationFailed
        let client = SoulNestOpenClawGatewayClient(connection: connection) { FakeChatTransport() }
        let endpoint = try SoulNestGatewayEndpoint(url: XCTUnwrap(URL(string: "wss://gateway.example.test")))

        do {
            try await client.connect(to: endpoint)
            XCTFail("Expected authenticationFailed")
        } catch {
            XCTAssertEqual(error as? SoulNestGatewayError, .authenticationFailed)
        }
        XCTAssertEqual(connection.connectedEndpoint, endpoint)
    }

    func testConnectSuccessUpdatesState() async throws {
        let connection = MockSoulNestGatewayConnection(state: .connecting)
        let client = SoulNestOpenClawGatewayClient(connection: connection) { FakeChatTransport() }
        let endpoint = try SoulNestGatewayEndpoint(url: XCTUnwrap(URL(string: "wss://gateway.example.test")))

        try await client.connect(to: endpoint)

        XCTAssertEqual(client.state, .connected)
    }

    func testDisconnectAndCancelPairingDelegateToConnection() async {
        let connection = MockSoulNestGatewayConnection(state: .connected)
        let client = SoulNestOpenClawGatewayClient(connection: connection) { FakeChatTransport() }

        await client.disconnect()
        await client.cancelPairing()

        XCTAssertEqual(connection.disconnectCount, 1)
        XCTAssertEqual(connection.cancelPairingCount, 1)
    }

    func testConnectionChangesForwardAsEvents() async {
        let connection = MockSoulNestGatewayConnection(state: .connecting)
        let client = SoulNestOpenClawGatewayClient(connection: connection) { FakeChatTransport() }
        let collector = EventCollector(stream: client.events)
        defer { collector.cancel() }

        connection.state = .connected
        connection.emitChange()

        await self.waitUntil { collector.containsConnectionState(.connected) }
    }

    func testConnectionParametersFromEndpoint() throws {
        let wss = try SoulNestGatewayEndpoint(url: XCTUnwrap(URL(string: "wss://gateway.example.test")))
        XCTAssertEqual(
            SoulNestOpenClawGatewayConnection.connectionParameters(from: wss),
            SoulNestOpenClawGatewayConnection.ConnectionParameters(
                host: "gateway.example.test",
                port: 0,
                useTLS: true,
                stableID: nil))

        let lan = try SoulNestGatewayEndpoint(
            url: XCTUnwrap(URL(string: "ws://192.168.1.10:18789")),
            stableID: "manual|192.168.1.10|18789")
        XCTAssertEqual(
            SoulNestOpenClawGatewayConnection.connectionParameters(from: lan),
            SoulNestOpenClawGatewayConnection.ConnectionParameters(
                host: "192.168.1.10",
                port: 18789,
                useTLS: false,
                stableID: "manual|192.168.1.10|18789"))

        let http = try SoulNestGatewayEndpoint(url: XCTUnwrap(URL(string: "http://gateway.example.test")))
        XCTAssertEqual(
            SoulNestOpenClawGatewayConnection.connectionParameters(from: http),
            SoulNestOpenClawGatewayConnection.ConnectionParameters(
                host: "gateway.example.test",
                port: 0,
                useTLS: false,
                stableID: nil))
    }

    func testMapsGatewayConnectionProblemsToSoulNestErrors() {
        let auth = GatewayConnectionProblem(
            kind: .gatewayAuthTokenMismatch,
            owner: .both,
            title: "token mismatch",
            message: "message",
            retryable: false,
            pauseReconnect: true)
        XCTAssertEqual(
            SoulNestOpenClawGatewayConnection.mapError(from: auth),
            .authenticationFailed)

        let network = GatewayConnectionProblem(
            kind: .timeout,
            owner: .network,
            title: "timed out",
            message: "message",
            retryable: true,
            pauseReconnect: false)
        XCTAssertEqual(
            SoulNestOpenClawGatewayConnection.mapError(from: network),
            .networkUnavailable)

        let pairing = GatewayConnectionProblem(
            kind: .pairingRequired,
            owner: .gateway,
            title: "pairing",
            message: "message",
            requestId: "req-1",
            retryable: false,
            pauseReconnect: true)
        XCTAssertEqual(
            SoulNestOpenClawGatewayConnection.mapError(from: pairing),
            .pairingFailed)

        let tls = GatewayConnectionProblem(
            kind: .tlsCertificateUntrusted,
            owner: .iphone,
            title: "tls",
            message: "message",
            retryable: false,
            pauseReconnect: true)
        XCTAssertEqual(
            SoulNestOpenClawGatewayConnection.mapError(from: tls),
            .gatewayUnavailable)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool) async
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out after \(timeout)s waiting for gateway event")
    }
}

@MainActor
private final class MockSoulNestGatewayConnection: SoulNestGatewayConnection {
    var state: SoulNestGatewayConnectionState
    var connectError: SoulNestGatewayError?
    var connectedEndpoint: SoulNestGatewayEndpoint?
    var disconnectCount = 0
    var cancelPairingCount = 0

    private let continuation: AsyncStream<Void>.Continuation
    let changes: AsyncStream<Void>

    init(state: SoulNestGatewayConnectionState = .disconnected) {
        self.state = state
        var continuation: AsyncStream<Void>.Continuation!
        self.changes = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func connect(to endpoint: SoulNestGatewayEndpoint) async {
        self.connectedEndpoint = endpoint
        if let connectError {
            self.state = .failed(connectError)
            self.continuation.yield(())
            return
        }
        self.state = .connected
        self.continuation.yield(())
    }

    func disconnect() async {
        self.disconnectCount += 1
        self.state = .disconnected
        self.continuation.yield(())
    }

    func cancelPairing() async {
        self.cancelPairingCount += 1
        self.state = .disconnected
        self.continuation.yield(())
    }

    func emitChange() {
        self.continuation.yield(())
    }
}

@MainActor
private final class EventCollector {
    private(set) var events: [SoulNestGatewayEvent] = []
    private var task: Task<Void, Never>?

    init(stream: AsyncStream<SoulNestGatewayEvent>) {
        self.task = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.events.append(event)
            }
        }
    }

    func cancel() {
        self.task?.cancel()
    }

    func containsConnectionState(_ expected: SoulNestGatewayConnectionState) -> Bool {
        self.events.contains { $0 == .connectionChanged(expected) }
    }

    func containsAssistantText(requestID: String, isFinal: Bool) -> Bool {
        self.events.contains { event in
            guard case let .assistantText(eventID, _, final) = event else { return false }
            return eventID == requestID && final == isFinal
        }
    }

    func containsRequestFailed(requestID: String? = nil, error: SoulNestGatewayError? = nil) -> Bool {
        self.events.contains { event in
            guard case let .requestFailed(eventID, eventError) = event else { return false }
            if let requestID, requestID != eventID { return false }
            if let error, error != eventError { return false }
            return true
        }
    }
}

private final class FakeChatTransport: OpenClawChatTransport, @unchecked Sendable {
    struct SendCall: Equatable {
        let sessionKey: String
        let message: String
    }

    struct AbortCall: Equatable {
        let sessionKey: String
        let runId: String
    }

    private struct State: Sendable {
        var sendCalls: [SendCall] = []
        var abortCalls: [AbortCall] = []
        var eventsToEmit: [OpenClawChatTransportEvent] = []
        var sendError: (any Error & Sendable)?
        var abortError: (any Error & Sendable)?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var sendCalls: [SendCall] {
        self.lock.withLock { $0.sendCalls }
    }

    var abortCalls: [AbortCall] {
        self.lock.withLock { $0.abortCalls }
    }

    var eventsToEmit: [OpenClawChatTransportEvent] {
        get { self.lock.withLock { $0.eventsToEmit } }
        set { self.lock.withLock { $0.eventsToEmit = newValue } }
    }

    var sendError: (any Error & Sendable)? {
        get { self.lock.withLock { $0.sendError } }
        set { self.lock.withLock { $0.sendError = newValue } }
    }

    var abortError: (any Error & Sendable)? {
        get { self.lock.withLock { $0.abortError } }
        set { self.lock.withLock { $0.abortError = newValue } }
    }

    func abortRun(sessionKey: String, runId: String) async throws {
        if let abortError {
            throw abortError
        }
        self.lock.withLock { state in
            state.abortCalls.append(.init(sessionKey: sessionKey, runId: runId))
        }
    }

    func requestHistory(sessionKey: String) async throws -> OpenClawChatHistoryPayload {
        OpenClawChatHistoryPayload(
            sessionKey: sessionKey,
            sessionId: nil,
            messages: nil,
            thinkingLevel: nil)
    }

    func requestHealth(timeoutMs _: Int) async throws -> Bool {
        true
    }

    func sendMessage(
        sessionKey: String,
        message: String,
        thinking: String,
        idempotencyKey: String,
        attachments: [OpenClawChatAttachmentPayload]) async throws -> OpenClawChatSendResponse
    {
        if let sendError {
            throw sendError
        }
        let count = self.lock.withLock { state in
            state.sendCalls.append(.init(sessionKey: sessionKey, message: message))
            return state.sendCalls.count
        }
        return OpenClawChatSendResponse(runId: "run-\(count)", status: "ok")
    }

    func events() -> AsyncStream<OpenClawChatTransportEvent> {
        AsyncStream { continuation in
            let events = self.lock.withLock { $0.eventsToEmit }
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
