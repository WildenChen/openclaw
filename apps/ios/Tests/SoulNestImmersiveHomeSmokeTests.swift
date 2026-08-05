import SwiftUI
import Testing
import UIKit
@testable import OpenClaw

/// Presentation smoke tests for the immersive character home: launch resolves
/// Yujie through the asset resolver, a send reaches the mock Gateway, and the
/// assistant response becomes visible in the chat panel.
struct SoulNestImmersiveHomeSmokeTests {
    @MainActor private static func host(_ view: some View, size: CGSize? = nil) -> UIWindow {
        let frame = CGRect(origin: .zero, size: size ?? CGSize(width: 393, height: 852))
        let window = UIWindow(frame: frame)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    @MainActor private static func makeConnectedSession() async throws
        -> (client: MockSoulNestGatewayClient, session: SoulNestGatewaySession)
    {
        let client = MockSoulNestGatewayClient()
        let session = SoulNestGatewaySession(client: client)
        let endpoint = try SoulNestGatewayEndpoint(url: URL(string: "wss://gateway.example.test")!)
        await session.connect(to: endpoint)
        return (client, session)
    }

    @MainActor private func waitFor(
        _ timeout: TimeInterval = 2,
        until condition: @MainActor @Sendable () -> Bool) async
    {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
    }

    @Test @MainActor func `launch resolves Yujie artwork through the resolver`() {
        let session = SoulNestGatewaySession(client: MockSoulNestGatewayClient())
        let window = Self.host(
            SoulNestCharacterHomeView(
                gatewaySession: session,
                isPresented: .constant(true)))
        defer { window.isHidden = true }

        var loader = SoulNestCharacterArtworkLoader()
        let resolved = loader.resolve(.idle)
        #expect(resolved != nil)
        #expect(resolved?.requestedState == .idle)
        let image = resolved.flatMap { loader.image(for: $0.asset) }
        #expect(image != nil)
    }

    @Test @MainActor func `send reaches the mock gateway and the response is visible`() async throws {
        let (client, session) = try await Self.makeConnectedSession()
        let lifecycle = SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: .yujie)
        _ = lifecycle.createConversation()
        let store = SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: session,
            lifecycle: lifecycle)

        let window = Self.host(
            SoulNestImmersiveChatView(store: store),
            size: CGSize(width: 393, height: 400))
        defer { window.isHidden = true }

        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)

        client.emitText(requestID: requestID, text: "Hi", isFinal: true)
        await self.waitFor { store.assistantText(for: requestID) == "Hi" }

        #expect(store.messages.count == 2)
        #expect(store.messages[0].role == .user)
        #expect(store.assistantText(for: requestID) == "Hi")
        #expect(store.isGenerating == false)
    }

    @Test @MainActor func `disconnected session presents the offline scene`() {
        let session = SoulNestGatewaySession(client: MockSoulNestGatewayClient())
        let window = Self.host(
            SoulNestCharacterHomeView(
                gatewaySession: session,
                isPresented: .constant(true)))
        defer { window.isHidden = true }

        #expect(session.state == .disconnected)
        #expect(session.state.isConnected == false)
        #expect(SoulNestGatewayConnectionState.disconnected.characterState == .offline)
        #expect(SoulNestGatewayConnectionState.connected.characterState == .idle)
        #expect(SoulNestGatewayConnectionState.reconnecting(attempt: 1).characterState == .thinking)
    }

    @Test @MainActor func `hosted chat hosts the stop control and cancels the turn`() async throws {
        let (client, session) = try await Self.makeConnectedSession()
        let lifecycle = SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: .yujie)
        _ = lifecycle.createConversation()
        let store = SoulNestImmersiveChatStore(
            profile: .yujie,
            gatewaySession: session,
            lifecycle: lifecycle)

        let window = Self.host(
            SoulNestImmersiveChatView(store: store),
            size: CGSize(width: 393, height: 400))
        defer { window.isHidden = true }

        await store.sendText("Hello")
        let requestID = try #require(store.messages.last?.requestID)
        client.emitText(requestID: requestID, text: "Partial")

        await self.waitFor { store.characterState == .talking }
        #expect(store.characterState == .talking)

        await store.stopGenerating()
        await self.waitFor { store.messages.last?.status == .cancelled }

        #expect(store.isGenerating == false)
        #expect(client.abortCalls.count == 1)
        #expect(store.messages.last?.text == "Partial")
    }
}
