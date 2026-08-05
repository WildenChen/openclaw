import Foundation
import Observation

/// Observable store for the immersive chat UI. Owns the message list and
/// delegates gateway communication to `SoulNestGatewaySession`.
@MainActor
@Observable
final class SoulNestImmersiveChatStore {
    private let gatewaySession: SoulNestGatewaySession
    private let lifecycle: SoulNestConversationLifecycle
    private var requestEventsTask: Task<Void, Never>?

    let profile: SoulNestAgentProfile

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

    /// True when the gateway connection is not usable for a text turn.
    var isOffline: Bool {
        !self.gatewaySession.state.isConnected
    }

    /// The state the character scene should present. A newly started turn is
    /// thinking until the first assistant text arrives, then talking while the
    /// response streams. Completion falls back to the connection-derived state.
    var characterState: SoulNestCharacterState {
        guard self.gatewaySession.isGenerating else {
            return self.gatewaySession.state.characterState
        }

        if let requestID = self.messages.last(where: { $0.role == .assistant })?.requestID,
           !self.assistantText(for: requestID).isEmpty
        {
            return .talking
        }

        return .thinking
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
        self.observeRequestEvents()
    }

    isolated deinit {
        self.requestEventsTask?.cancel()
    }

    func startNewConversation() {
        _ = self.lifecycle.createConversation()
        self.messages = []
        self.showError = false
    }

    func sendText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard case let .ready(sessionKey: sessionKey) = lifecycle.status else { return }

        self.isSending = true
        self.showError = false

        let userMessage = SoulNestChatMessage(
            id: UUID(),
            role: .user,
            text: trimmed,
            status: .completed,
            requestID: nil)
        self.messages.append(userMessage)

        do {
            let runID = try await gatewaySession.sendText(trimmed, sessionKey: sessionKey)
            let assistantMessage = SoulNestChatMessage(
                id: UUID(),
                role: .assistant,
                text: "",
                status: .queued,
                requestID: runID)
            self.messages.append(assistantMessage)
        } catch {
            self.showError = true
            self.removeLastUserMessage()
        }

        self.isSending = false
    }

    /// Stops the in-flight turn. The gateway run is cancelled and the partial
    /// text stays visible with a cancelled status.
    func stopGenerating() async {
        await self.gatewaySession.cancelCurrentRequest()
    }

    /// Retries the last failed or cancelled turn in place: the original user
    /// message is kept, a new request starts on the same session key, and the
    /// failed partial response stays visible below it.
    func retryLastFailedTurn() async {
        guard case let .ready(sessionKey: sessionKey) = lifecycle.status else { return }
        guard let failedIndex = self.messages.lastIndex(where: {
            $0.role == .assistant && $0.isRetryable
        }) else { return }
        guard let userIndex = self.messages[..<failedIndex].lastIndex(where: {
            $0.role == .user
        }) else { return }
        let text = self.messages[userIndex].text

        self.isSending = true
        self.showError = false
        do {
            let runID = try await self.gatewaySession.sendText(text, sessionKey: sessionKey)
            let retryMessage = SoulNestChatMessage(
                id: UUID(),
                role: .assistant,
                text: "",
                status: .queued,
                requestID: runID)
            self.messages.insert(retryMessage, at: failedIndex + 1)
        } catch {
            self.showError = true
        }
        self.isSending = false
    }

    func assistantText(for requestID: String) -> String {
        self.gatewaySession.assistantText[requestID] ?? ""
    }

    private func removeLastUserMessage() {
        if let last = messages.last, last.role == .user {
            self.messages.removeLast()
        }
    }

    private func observeRequestEvents() {
        self.requestEventsTask?.cancel()
        let gatewaySession = self.gatewaySession
        self.requestEventsTask = Task { [weak self] in
            for await event in gatewaySession.requestEvents {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: SoulNestRequestEvent) {
        switch event {
        case let .started(requestID):
            self.updateStatus(for: requestID, to: .thinking)
        case let .textUpdated(requestID):
            self.updateStatus(for: requestID, to: .streaming)
        case let .completed(requestID):
            self.commit(requestID, status: .completed)
        case let .failed(requestID, error):
            if error == .sessionExpired {
                self.recoverExpiredSession()
            }
            let status: SoulNestChatMessageStatus = error == .cancelled ? .cancelled : .failed(error)
            self.commit(requestID, status: status)
        }
    }

    private func updateStatus(for requestID: String, to status: SoulNestChatMessageStatus) {
        guard let index = self.messages.firstIndex(where: { $0.requestID == requestID }) else {
            return
        }
        self.messages[index] = self.messages[index].withStatus(status)
    }

    /// Commits the final/partial gateway snapshot as the display text and marks
    /// the message terminal, so it stays stable after the turn ends.
    private func commit(_ requestID: String, status: SoulNestChatMessageStatus) {
        guard let index = self.messages.firstIndex(where: { $0.requestID == requestID }) else {
            return
        }
        let snapshot = self.gatewaySession.assistantText[requestID] ?? ""
        self.messages[index] = self.messages[index].commit(snapshot, status: status)
    }

    /// A `.sessionExpired` gateway failure means the OpenClaw session was
    /// replaced elsewhere; the lifecycle issues a fresh generation without
    /// replaying transcript.
    private func recoverExpiredSession() {
        guard let conversationID = self.lifecycle.currentConversationID else { return }
        let lifecycle = self.lifecycle
        Task {
            await lifecycle.handleSessionExpired(for: conversationID)
        }
    }
}
