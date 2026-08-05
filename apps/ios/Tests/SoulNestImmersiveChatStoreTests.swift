import Foundation
import Testing
@testable import OpenClaw

/// Tests for `SoulNestImmersiveChatStore` and the assistant text streaming flow.
@MainActor
struct SoulNestImmersiveChatStoreTests {
    /// Polls until `condition` holds, yielding to the main actor so the
    /// session's event task can deliver emitted gateway events.
    private func waitFor(
        _ timeout: TimeInterval = 2,
        until condition: @MainActor @Sendable () -> Bool) async
    {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
    }

    /// Drives a fully connected session so `sendText` reaches the mock client.
    private func makeConnectedStore() async throws
        -> (client: MockSoulNestGatewayClient, session: SoulNestGatewaySession, store: SoulNestImmersiveChatStore)
    {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let lifecycle = SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: .yujie)
        _ = lifecycle.createConversation()
        let endpoint = try SoulNestGatewayEndpoint(
            url: URL(string: "wss://gateway.example.test")!)
        await session.connect(to: endpoint)
        let store = SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: session,
            lifecycle: lifecycle)
        return (client, session, store)
    }

    /// When `sendText` succeeds, the store should add a user message and an
    /// assistant placeholder with the correct requestID.
    @Test func `send text adds user and assistant messages`() async throws {
        let (_, _, store) = try await self.makeConnectedStore()

        await store.sendText("Hello")

        #expect(store.messages.count == 2)
        #expect(store.messages[0].role == .user)
        #expect(store.messages[0].text == "Hello")
        #expect(store.messages[1].role == .assistant)
        #expect(store.messages[1].isStreaming == true)
        #expect(store.messages[1].requestID != nil)
    }

    /// When `sendText` fails, the store should not leave a user message behind.
    @Test func `send text failure removes user message`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()
        client.sendShouldFail = true

        await store.sendText("Hi")

        #expect(store.messages.isEmpty)
        #expect(store.showError == true)
    }

    /// Gateway chat events carry the full assistant snapshot on each update, so
    /// a later event replaces the earlier text for the same requestID.
    @Test func `assistant text replaces on each full-snapshot event`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()

        await store.sendText("Hello")

        let requestID = try #require(store.messages.last?.requestID)

        client.emitText(requestID: requestID, text: "Hello")
        client.emitText(requestID: requestID, text: "Hello, world!")

        await self.waitFor { store.assistantText(for: requestID) == "Hello, world!" }

        #expect(store.assistantText(for: requestID) == "Hello, world!")
    }

    /// A new turn starts in thinking, switches to talking when assistant text
    /// arrives, and returns to idle after the final event.
    @Test func `character state follows thinking talking idle transition`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()

        #expect(store.characterState == .idle)

        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        #expect(store.characterState == .thinking)

        client.emitText(requestID: requestID, text: "Hi")
        await self.waitFor { store.characterState == .talking }

        #expect(store.characterState == .talking)

        client.emitText(requestID: requestID, text: "Hi there", isFinal: true)
        await self.waitFor { store.characterState == .idle }

        #expect(store.characterState == .idle)
        #expect(store.assistantText(for: requestID) == "Hi there")
    }

    /// When the gateway emits a final event, `isGenerating` should be false and
    /// the final snapshot should still be captured as the assistant text.
    @Test func `is generating false after final event`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()

        await store.sendText("Hello")

        let requestID = try #require(store.messages.last?.requestID)

        #expect(store.isGenerating == true)

        client.emitText(requestID: requestID, text: "Hi", isFinal: true)

        await self.waitFor { store.isGenerating == false }

        #expect(store.isGenerating == false)
        #expect(store.assistantText(for: requestID) == "Hi")
    }

    // MARK: - Cancel

    /// Stopping the turn calls the underlying `abortRun` and marks the message
    /// cancelled while keeping the partial text visible.
    @Test func `stop cancels the underlying run and keeps partial text`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()
        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        client.emitText(requestID: requestID, text: "Partial reply")
        await self.waitFor { store.assistantText(for: requestID) == "Partial reply" }

        await store.stopGenerating()

        await self.waitFor { store.messages.last?.status == .cancelled }

        #expect(store.isGenerating == false)
        #expect(client.abortCalls.count == 1)
        #expect(client.abortCalls.first?.runId == requestID)
        #expect(store.messages.last?.status == .cancelled)
        #expect(store.messages.last?.isRetryable == true)
        #expect(store.messages.last?.text == "Partial reply")
    }

    /// An aborted gateway event (the "aborted" chat state) also maps to a
    /// cancelled turn.
    @Test func `aborted gateway event maps to cancelled`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()
        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        client.emitFailure(requestID: requestID, error: .cancelled)

        await self.waitFor { store.messages.last?.status == .cancelled }

        #expect(store.isGenerating == false)
    }

    // MARK: - Retry

    /// A failed turn retries in place: the user message is not duplicated, the
    /// retry uses a fresh request id on the same session key, and the failed
    /// partial stays in the transcript.
    @Test func `failed turn retries in place without duplicating the user message`() async throws {
        let (client, session, store) = try await self.makeConnectedStore()
        await store.sendText("Hello")
        let firstID = try #require(store.messages.last?.requestID)
        let sessionKey = try #require(store.currentSessionKey)

        client.emitFailure(requestID: firstID, error: .gatewayUnavailable)
        await self.waitFor { store.messages.last?.status == .failed(.gatewayUnavailable) }
        #expect(store.messages.filter { $0.role == .user }.count == 1)

        await store.retryLastFailedTurn()

        await self.waitFor { store.messages.last?.requestID != firstID }

        let retryMessage = try #require(store.messages.last)
        #expect(retryMessage.role == .assistant)
        #expect(retryMessage.requestID != nil)
        #expect(retryMessage.isStreaming)
        #expect(store.messages.filter { $0.role == .user }.count == 1)
        #expect(store.messages.first(where: { $0.role == .user })?.text == "Hello")
        #expect(store.messages.contains { $0.status == .failed(.gatewayUnavailable) })
        #expect(client.sentTexts.count == 2)
        #expect(client.sentTexts.last?.text == "Hello")
        #expect(client.sentTexts.last?.sessionKey == sessionKey)
        #expect(session.assistantText[firstID] != nil)
    }

    // MARK: - Timeout

    /// A stalled turn times out: the underlying run is cancelled, `isGenerating`
    /// stops, and the message becomes a retryable failure.
    @Test func `stalled turn times out and surfaces a retryable failure`() async throws {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client, responseTimeout: .milliseconds(20))
        let lifecycle = SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: .yujie)
        _ = lifecycle.createConversation()
        let endpoint = try SoulNestGatewayEndpoint(
            url: #require(URL(string: "wss://gateway.example.test")))
        await session.connect(to: endpoint)
        let store = SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: session,
            lifecycle: lifecycle)

        await store.sendText("Hello")

        await self.waitFor { store.messages.last?.status == .failed(.requestTimedOut) }

        #expect(store.isGenerating == false)
        #expect(client.abortCalls.count == 1)
        #expect(store.messages.last?.isRetryable == true)
    }

    // MARK: - Connection loss

    /// Dropping the connection ends the in-flight turn with a network failure,
    /// keeps the partial text, and a later reconnect does not replay or resend
    /// anything.
    @Test func `connection loss ends the active turn and reconnect does not resend`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()
        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        client.emitText(requestID: requestID, text: "Partial reply")
        await self.waitFor { store.assistantText(for: requestID) == "Partial reply" }

        client.emitConnection(.disconnected)

        await self.waitFor { store.messages.last?.status == .failed(.networkUnavailable) }

        #expect(store.isGenerating == false)
        #expect(store.messages.last?.text == "Partial reply")

        client.emitConnection(.connected)
        await self.waitFor { !store.isOffline }

        #expect(store.messages.count == 2)
        #expect(client.sentTexts.count == 1)
    }

    // MARK: - Malformed and stale events

    /// Events for unknown or empty request ids are ignored so a stale or
    /// malformed event cannot pollute the visible response.
    @Test func `stale events for unknown request ids are ignored`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()
        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        client.emitText(requestID: "stale-other", text: "pollution")
        client.emitFailure(requestID: "stale-other", error: .gatewayUnavailable)
        client.emitText(requestID: "", text: "pollution", isFinal: true)
        client.emitText(requestID: requestID, text: "Good", isFinal: true)

        await self.waitFor { store.messages.last?.status == .completed }

        #expect(store.assistantText(for: "stale-other").isEmpty)
        #expect(store.assistantText(for: requestID) == "Good")
        #expect(store.messages.last?.text == "Good")
        #expect(store.isGenerating == false)
    }

    /// A duplicate final event after the turn completed is ignored.
    @Test func `duplicate final event is ignored`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()
        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        client.emitText(requestID: requestID, text: "Done", isFinal: true)
        await self.waitFor { store.messages.last?.status == .completed }

        client.emitText(requestID: requestID, text: "Done, changed", isFinal: true)
        await self.waitFor { store.isGenerating == false }

        #expect(store.assistantText(for: requestID) == "Done")
        #expect(store.messages.last?.text == "Done")
        #expect(store.messages.last?.status == .completed)
    }

    /// A non-final chunk after the final event is ignored.
    @Test func `chunk after final event is ignored`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()
        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        client.emitText(requestID: requestID, text: "Done", isFinal: true)
        await self.waitFor { store.messages.last?.status == .completed }

        client.emitText(requestID: requestID, text: "Extra")
        await self.waitFor { store.isGenerating == false }

        #expect(store.assistantText(for: requestID) == "Done")
        #expect(store.messages.last?.text == "Done")
        #expect(store.messages.last?.status == .completed)
    }

    // MARK: - Session expiry

    /// A `.sessionExpired` gateway failure drives the lifecycle to issue a
    /// fresh session key without replaying transcript.
    @Test func `session expired failure replaces the session key`() async throws {
        let (client, _, store) = try await self.makeConnectedStore()
        let originalKey = try #require(store.currentSessionKey)
        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        client.emitFailure(requestID: requestID, error: .sessionExpired)

        await self.waitFor { store.currentSessionKey != originalKey }

        #expect(store.messages.last?.status == .failed(.sessionExpired))
        #expect(store.isGenerating == false)
    }
}
