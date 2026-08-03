import Foundation

struct SoulNestConversationSession: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let profileID: String
    let openClawAgentID: String
    let generation: UUID
    let sessionKey: String
    let createdAt: Date
    var updatedAt: Date
}

/// Persists only the mapping between an iOS conversation and its OpenClaw session key.
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
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init)
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

    func session(
        for conversationID: UUID,
        profile: SoulNestAgentProfile = .yujie) -> SoulNestConversationSession
    {
        if let existing = self.sessions[conversationID],
           Self.isValid(existing, for: profile)
        {
            return existing
        }

        return self.replaceSession(for: conversationID, profile: profile)
    }

    /// Replaces an expired, missing, or explicitly reset remote session without
    /// changing the local conversation identifier.
    @discardableResult
    func replaceSession(
        for conversationID: UUID,
        profile: SoulNestAgentProfile = .yujie) -> SoulNestConversationSession
    {
        precondition(profile.isValid, "SoulNest requires a valid agent profile")

        let timestamp = self.now()
        let generation = self.makeUUID()
        let baseKey = [
            "soulnest-ios",
            conversationID.uuidString.lowercased(),
            generation.uuidString.lowercased(),
        ].joined(separator: "-")
        let mapping = SoulNestConversationSession(
            id: conversationID,
            profileID: profile.id,
            openClawAgentID: profile.openClawAgentID,
            generation: generation,
            sessionKey: SessionKey.makeAgentSessionKey(
                agentId: profile.openClawAgentID,
                baseKey: baseKey),
            createdAt: self.sessions[conversationID]?.createdAt ?? timestamp,
            updatedAt: timestamp)

        self.sessions[conversationID] = mapping
        self.persist()
        return mapping
    }

    func removeSession(for conversationID: UUID) {
        guard self.sessions.removeValue(forKey: conversationID) != nil else { return }
        self.persist()
    }

    func removeAllSessions() {
        self.sessions.removeAll()
        self.defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        let records = self.allSessions
        guard let data = try? JSONEncoder().encode(records) else {
            assertionFailure("SoulNest conversation session mappings should always be encodable")
            return
        }
        self.defaults.set(data, forKey: Self.storageKey)
    }

    private static func loadSessions(from defaults: UserDefaults) -> [UUID: SoulNestConversationSession] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SoulNestConversationSession].self, from: data)
        else {
            return [:]
        }

        return decoded.reduce(into: [:]) { result, mapping in
            guard Self.isValid(mapping, for: .yujie), result[mapping.id] == nil else { return }
            result[mapping.id] = mapping
        }
    }

    private static func isValid(
        _ mapping: SoulNestConversationSession,
        for profile: SoulNestAgentProfile) -> Bool
    {
        mapping.profileID == profile.id &&
            mapping.openClawAgentID == profile.openClawAgentID &&
            SessionKey.agentId(from: mapping.sessionKey) == profile.openClawAgentID &&
            mapping.sessionKey.hasPrefix("agent:\(profile.openClawAgentID):soulnest-ios-")
    }
}
