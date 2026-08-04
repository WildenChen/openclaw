import Foundation
import Observation

/// Observable store for the immersive chat UI. Owns the message list and
/// delegates gateway communication to `SoulNestGatewaySession`.
@MainActor
@Observable
final class SoulNestImmersiveChatStore {
    private let gatewaySession: SoulNestGatewaySession
    private let lifecycle: SoulNestConversationLifecycle
    private let profile: SoulNestAgentProfile

    private(set) var messages: [SoulNestChatMessage] = []
    private(set) var isSending = false
    private(set) var showError = false

    var sessionStatus: SoulNestConversationSessionStatus {
        self.lifecycle.status
    }

    var currentSessionKey: String? {
        self.lifecycle.currentSessionKey
    }

    var isGenerating: Bool {
        self.gatewaySession.isGenerating
    }

    init(
        profile: SoulNestAgentProfile = .yujie,
        gatewaySession: SoulNestGatewaySession,
        lifecycle: SoulNestConversationLifecycle? = nil)
    {
        self.profile = profile
        self.gatewaySession = gatewaySession
        self.lifecycle = lifecycle ?? SoulNestConversationLifecycle(
            store: SoulNestConversationSessionStore(),
            profile: profile)
    }

    func startNewConversation() {
        let _ = self.lifecycle.createConversation()
        self.messages = []
        self.showError = false
    }

    func sendText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard case .ready(sessionKey: let sessionKey) = self.lifecycle.status else { return }

        self.isSending = true
        self.showError = false

        let userMessage = SoulNestChatMessage(
            id: UUID(),
            role: .user,
            text: trimmed,
            isStreaming: false,
            requestID: nil)
        self.messages.append(userMessage)

        do {
            let runID = try await self.gatewaySession.sendText(trimmed, sessionKey: sessionKey)
            let assistantMessage = SoulNestChatMessage(
                id: UUID(),
                role: .assistant,
                text: "",
                isStreaming: true,
                requestID: runID)
            self.messages.append(assistantMessage)
        } catch {
            self.showError = true
            self.removeLastUserMessage()
        }

        self.isSending = false
    }

    func assistantText(for requestID: String) -> String {
        self.gatewaySession.assistantText[requestID] ?? ""
    }

    private func removeLastUserMessage() {
        if let last = self.messages.last, last.role == .user {
            self.messages.removeLast()
        }
    }
}
