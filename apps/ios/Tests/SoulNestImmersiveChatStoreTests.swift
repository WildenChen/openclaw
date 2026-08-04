import Foundation
import Testing
@testable import OpenClaw

/// Tests for `SoulNestImmersiveChatStore` and the assistant text streaming flow.
struct SoulNestImmersiveChatStoreTests {
    /// When `sendText` succeeds, the store should add a user message and an
    /// assistant placeholder with the correct requestID.
    @Test func sendTextAddsUserAndAssistantMessages() async throws {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let lifecycle = SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: .yujie)

        client.simulateConnect()
        _ = lifecycle.createConversation()

        let store = SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: session,
            lifecycle: lifecycle)

        await store.sendText("Hello")

        #expect(store.messages.count == 2)
        #expect(store.messages[0].role == .user)
        #expect(store.messages[0].text == "Hello")
        #expect(store.messages[1].role == .assistant)
        #expect(store.messages[1].isStreaming == true)
        #expect(store.messages[1].requestID != nil)
    }

    /// When `sendText` fails, the store should not leave a user message behind.
    @Test func sendTextFailureRemovesUserMessage() async throws {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let lifecycle = SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: .yujie)

        client.simulateConnect()
        _ = lifecycle.createConversation()

        let store = SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: session,
            lifecycle: lifecycle)

        client.sendShouldFail = true

        await store.sendText("Hi")

        #expect(store.messages.isEmpty)
        #expect(store.showError == true)
    }

    /// When the gateway session receives assistant text events, the store
    /// should expose the accumulated text via `assistantText`.
    @Test func assistantTextAccumulatesFromGatewayEvents() async throws {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let lifecycle = SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: .yujie)

        client.simulateConnect()
        _ = lifecycle.createConversation()

        let store = SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: session,
            lifecycle: lifecycle)

        await store.sendText("Hello")

        let requestID = store.messages[1].requestID!

        client.emitText(requestID: requestID, text: "Hello")
        client.emitText(requestID: requestID, text: ", ")
        client.emitText(requestID: requestID, text: "world!")

        let accumulated = store.assistantText(for: requestID)
        #expect(accumulated == "Hello, world!")
    }

    /// When the gateway emits a final text event, `isGenerating` should be false.
    @Test func isGeneratingFalseAfterFinalEvent() async throws {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let lifecycle = SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: .yujie)

        client.simulateConnect()
        _ = lifecycle.createConversation()

        let store = SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: session,
            lifecycle: lifecycle)

        await store.sendText("Hello")

        let requestID = store.messages[1].requestID!

        #expect(store.isGenerating == true)

        client.emitText(requestID: requestID, text: "Hi", isFinal: true)

        #expect(store.isGenerating == false)
    }
}