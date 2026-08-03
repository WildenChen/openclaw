import Foundation
import Observation

@MainActor
@Observable
final class SoulNestAgentProfileStore {
    static let storageKey = "soulnest.agent-profile.v1"

    private let defaults: UserDefaults
    private(set) var current: SoulNestAgentProfile

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = Self.loadProfile(from: defaults) ?? .yujie

        // Repair missing, invalid, or corrupted non-sensitive profile metadata so
        // later launches always have the built-in Yujie profile available.
        if Self.loadProfile(from: defaults) == nil {
            self.persist(self.current)
        }
    }

    func save(_ profile: SoulNestAgentProfile) {
        guard profile.isValid else {
            self.resetToBuiltInYujie()
            return
        }

        // The first release supports only the existing OpenClaw Yujie agent.
        // Additional profile IDs are introduced explicitly by future issue #24.
        guard profile.id == SoulNestAgentProfile.yujie.id,
              profile.openClawAgentID == SoulNestAgentProfile.yujie.openClawAgentID
        else {
            self.resetToBuiltInYujie()
            return
        }

        self.current = profile
        self.persist(profile)
    }

    func resetToBuiltInYujie() {
        self.current = .yujie
        self.persist(.yujie)
    }

    private static func loadProfile(from defaults: UserDefaults) -> SoulNestAgentProfile? {
        guard let data = defaults.data(forKey: Self.storageKey),
              let profile = try? JSONDecoder().decode(SoulNestAgentProfile.self, from: data),
              profile.isValid,
              profile.id == SoulNestAgentProfile.yujie.id,
              profile.openClawAgentID == SoulNestAgentProfile.yujie.openClawAgentID
        else {
            return nil
        }
        return profile
    }

    private func persist(_ profile: SoulNestAgentProfile) {
        guard let data = try? JSONEncoder().encode(profile) else {
            assertionFailure("SoulNest Yujie profile should always be encodable")
            return
        }
        self.defaults.set(data, forKey: Self.storageKey)
    }
}
