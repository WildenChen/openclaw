import Foundation

/// Surface namespace encoded into a sessionKey so the same conversation on
/// different surfaces never shares a key. iOS and Telegram are isolated at the
/// key-encoding layer: a key whose prefix does not match the active surface is
/// treated as expired on load.
enum SoulNestConversationSurface: String, Codable, Sendable {
    case ios = "soulnest-ios"
    case telegram = "soulnest-telegram"
}

struct SoulNestConversationSession: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let profileID: String
    let openClawAgentID: String
    let generation: UUID
    let sessionKey: String
    let createdAt: Date
    var updatedAt: Date
}

/// Persists only the mapping between a surface conversation and its OpenClaw session key.
///
/// OpenClaw remains authoritative for transcript and memory. This store never keeps
/// message history and never replays local messages when a connection is restored.
@MainActor
final class SoulNestConversationSessionStore {
    static let storageKey = "soulnest.conversation-sessions.v1"

    private let defaults: UserDefaults
    private let now: () -> Date
    private let makeUUID: () -> UUID
    private var sessions: [UUID: SoulNestConversationSession]

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        makeUUID: @escaping () -> UUID = { UUID() })
    {
        self.defaults = defaults
        self.now = now
        self.makeUUID = makeUUID
        self.sessions = Self.loadSessions(from: defaults)
    }

    var allSessions: [SoulNestConversationSession] {
        self.sessions.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// Returns the existing session for `conversationID` and `surface` when it is
    /// still valid; otherwise replaces it in place so the local conversation id
    /// is preserved but a fresh generation/sessionKey is issued.
    @discardableResult
    func session(
        for conversationID: UUID,
        profile: SoulNestAgentProfile = .yujie,
        surface: SoulNestConversationSurface = .ios) -> SoulNestConversationSession
    {
        if let existing = self.sessions[conversationID],
           Self.isValid(existing, for: profile, surface: surface)
        {
            return existing
        }

        return self.replaceSession(for: conversationID, profile: profile, surface: surface)
    }

    /// Replaces an expired, missing, or explicitly reset remote session without
    /// changing the local conversation identifier.
    @discardableResult
    func replaceSession(
        for conversationID: UUID,
        profile: SoulNestAgentProfile = .yujie,
        surface: SoulNestConversationSurface = .ios) -> SoulNestConversationSession
    {
        precondition(profile.isValid, "SoulNest requires a valid agent profile")

        let timestamp = self.now()
        let generation = self.makeUUID()
        let baseKey = [
            surface.rawValue,
            conversationID.uuidString.lowercased(),
            generation.uuidString.lowercased(),
        ].joined(separator: "-")
        let session = SoulNestConversationSession(
            id: conversationID,
            profileID: profile.id,
            openClawAgentID: profile.openClawAgentID,
            generation: generation,
            sessionKey: SessionKey.makeAgentSessionKey(
                agentId: profile.openClawAgentID,
                baseKey: baseKey),
            createdAt: self.sessions[conversationID]?.createdAt ?? timestamp,
            updatedAt: timestamp)

        self.sessions[conversationID] = session
        self.persist()
        return session
    }

    func removeSession(for conversationID: UUID) {
        guard self.sessions.removeValue(forKey: conversationID) != nil else { return }
        self.persist()
    }

    func removeAllSessions() {
        self.sessions.removeAll()
        self.defaults.removeObject(forKey: Self.storageKey)
    }

    /// True when a persisted session is still valid for this profile+surface.
    /// Sessions whose surface prefix no longer matches are treated as expired so
    /// the store can rebuild them, which is what keeps surfaces isolated.
    func isValidSession(
        _ session: SoulNestConversationSession,
        profile: SoulNestAgentProfile,
        surface: SoulNestConversationSurface) -> Bool
    {
        Self.isValid(session, for: profile, surface: surface)
    }

    private func persist() {
        let records = self.allSessions
        guard let data = try? JSONEncoder().encode(records) else {
            assertionFailure("SoulNest conversation session mappings should always be encodable")
            return
        }
        self.defaults.set(data, forKey: Self.storageKey)
    }

    private static func surface(of sessionKey: String) -> SoulNestConversationSurface? {
        guard sessionKey.hasPrefix("agent:") else { return nil }
        for surface in SoulNestConversationSurface.allCases
            where sessionKey.contains("\(surface.rawValue)-")
        {
            return surface
        }
        return nil
    }

    private static func isValid(
        _ session: SoulNestConversationSession,
        for profile: SoulNestAgentProfile) -> Bool
    {
        session.profileID == profile.id &&
            session.openClawAgentID == profile.openClawAgentID &&
            SessionKey.agentId(from: session.sessionKey) == profile.openClawAgentID
    }

    private static func isValid(
        _ session: SoulNestConversationSession,
        for profile: SoulNestAgentProfile,
        surface: SoulNestConversationSurface) -> Bool
    {
        guard self.isValid(session, for: profile),
              let sessionSurface = Self.surface(of: session.sessionKey),
              sessionSurface == surface
        else {
            return false
        }
        return session.sessionKey.hasPrefix("agent:\(profile.openClawAgentID):\(surface.rawValue)-")
    }

    private static func loadSessions(from defaults: UserDefaults) -> [UUID: SoulNestConversationSession] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SoulNestConversationSession].self, from: data)
        else {
            return [:]
        }

        let profile = SoulNestAgentProfile.yujie
        return decoded.reduce(into: [:]) { result, session in
            guard result[session.id] == nil else { return }
            // Validate per the session's own surface: an ios session is never
            // valid as a telegram session and vice versa, so cross-surface
            // mappings are rebuilt here rather than reused.
            let surface = Self.surface(of: session.sessionKey)
            guard let surface, Self.isValid(session, for: profile, surface: surface)
            else { return }
            result[session.id] = session
        }
    }
}

extension SoulNestConversationSurface: CaseIterable {}
