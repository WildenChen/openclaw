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
}
