import Foundation

/// Session lifecycle states surfaced to the UI. Intentionally opaque: it never
/// carries a bottom-layer payload (sessionKey is surfaced only on `.ready`).
enum SoulNestConversationSessionStatus: Equatable, Sendable {
    case ready(sessionKey: String)
    case expired
    case missing
    case invalid
}

enum SoulNestConversationLifecycleError: Error, Equatable, Sendable {
    case invalidProfile
    case notConnected
    case sessionExpired
    case sessionMissing
}

/// Upper conversation flow that owns the Conversation ID -> sessionKey mapping
/// and the surface-local lifecycle: new conversation, restore, switch, reset,
/// expired/nonexistent, and safe session replacement.
///
/// This layer never replays local history: it holds only the mapping, it never
/// calls the Gateway history endpoint, and a safe replacement always issues a
/// fresh generation/sessionKey to OpenClaw without forwarding prior transcript.
@MainActor
final class SoulNestConversationLifecycle {
    private let store: SoulNestConversationSessionStore
    private let profile: SoulNestAgentProfile
    private let surface: SoulNestConversationSurface
    private let onResetSession: (@Sendable (String) async throws -> Void)?
    private var activeConversationID: UUID?
    private var activeSessionKey: String?
    private(set) var status: SoulNestConversationSessionStatus

    init(
        store: SoulNestConversationSessionStore,
        profile: SoulNestAgentProfile = .yujie,
        surface: SoulNestConversationSurface = .ios,
        resetSession onResetSession: (@Sendable (String) async throws -> Void)? = nil)
    {
        self.store = store
        self.profile = profile
        self.surface = surface
        self.onResetSession = onResetSession
        self.status = .missing
    }

    /// Starts a brand-new conversation and issues its first session key.
    func createConversation() -> UUID {
        let conversationID = UUID()
        let session = self.store.session(for: conversationID, profile: self.profile, surface: self.surface)
        self.activeConversationID = conversationID
        self.activeSessionKey = session.sessionKey
        self.status = .ready(sessionKey: session.sessionKey)
        return conversationID
    }

    /// Restores a conversation by id, reusing its session key when still valid
    /// and issuing a safe replacement when expired.
    func restoreConversation(id: UUID) async {
        let session = self.store.session(for: id, profile: self.profile, surface: self.surface)
        if self.store.isValidSession(session, profile: self.profile, surface: self.surface) {
            self.activeConversationID = id
            self.activeSessionKey = session.sessionKey
            self.status = .ready(sessionKey: session.sessionKey)
            return
        }
        await self.replaceSession(for: id)
    }

    /// Switches the active conversation. A switch recomputes the session key so a
    /// session expired by another surface is observed instead of reused.
    func switchConversation(to id: UUID) async {
        let session = self.store.session(for: id, profile: self.profile, surface: self.surface)
        if self.store.isValidSession(session, profile: self.profile, surface: self.surface) {
            self.activeConversationID = id
            self.activeSessionKey = session.sessionKey
            self.status = .ready(sessionKey: session.sessionKey)
            return
        }
        await self.replaceSession(for: id)
    }

    /// User-initiated reset: keeps the conversation id and issues a new generation.
    func resetSession(for conversationID: UUID) async throws {
        let previous = self.store.session(for: conversationID, profile: self.profile, surface: self.surface)
        let replacement = self.store.replaceSession(
            for: conversationID,
            profile: self.profile,
            surface: self.surface)

        assert(replacement.id == conversationID)
        assert(replacement.createdAt == previous.createdAt)
        assert(replacement.generation != previous.generation)
        assert(replacement.sessionKey != previous.sessionKey)

        self.activeConversationID = conversationID
        self.activeSessionKey = replacement.sessionKey
        self.status = .ready(sessionKey: replacement.sessionKey)
        try? await self.onResetSession?(replacement.sessionKey)
    }

    /// Handles a `.sessionExpired` gateway error: keeps the conversation id,
    /// bumps the generation, and resets the OpenClaw session without replaying
    /// transcript.
    func handleSessionExpired(for conversationID: UUID) async {
        await self.replaceSession(for: conversationID)
    }

    var currentSessionKey: String? {
        self.activeSessionKey
    }

    var currentConversationID: UUID? {
        self.activeConversationID
    }

    // MARK: - Private

    @discardableResult
    private func replaceSession(for conversationID: UUID) async -> Bool {
        let replacement = self.store.replaceSession(
            for: conversationID,
            profile: self.profile,
            surface: self.surface)

        self.activeConversationID = conversationID
        self.activeSessionKey = replacement.sessionKey
        self.status = .ready(sessionKey: replacement.sessionKey)
        try? await self.onResetSession?(replacement.sessionKey)
        return true
    }
}
