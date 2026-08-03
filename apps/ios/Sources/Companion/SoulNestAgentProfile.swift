import Foundation

/// Non-sensitive client presentation and routing metadata for a SoulNest agent.
///
/// The profile intentionally does not contain SOUL text, durable memory, model
/// configuration, provider credentials, or Gateway credentials. Those remain
/// authoritative in OpenClaw as defined by the Companion Client architecture.
struct SoulNestAgentProfile: Codable, Equatable, Identifiable, Sendable {
    enum Capability: String, Codable, CaseIterable, Hashable, Sendable {
        case textChat
        case talkMode
        case imageAttachments
        case secretaryCards
        case deviceCapabilities
    }

    struct UIPreferences: Codable, Equatable, Sendable {
        enum HomeLayout: String, Codable, Sendable {
            case immersiveCharacter
        }

        var homeLayout: HomeLayout
        var showsSecretaryDrawer: Bool
        var preferredCharacterState: String

        static let yujieDefault = Self(
            homeLayout: .immersiveCharacter,
            showsSecretaryDrawer: true,
            preferredCharacterState: "idle")
    }

    let id: String
    let openClawAgentID: String
    var displayName: String
    var characterAssetPackID: String
    var sessionNamespace: String
    var capabilities: Set<Capability>
    var uiPreferences: UIPreferences

    var isValid: Bool {
        !self.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.openClawAgentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.characterAssetPackID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.sessionNamespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let yujie = Self(
        id: "yujie",
        openClawAgentID: "yujie",
        displayName: "語婕",
        characterAssetPackID: "yujie.default",
        sessionNamespace: "soulnest.yujie",
        capabilities: [
            .textChat,
            .talkMode,
            .imageAttachments,
            .secretaryCards,
            .deviceCapabilities,
        ],
        uiPreferences: .yujieDefault)

    /// The first SoulNest release deliberately exposes one profile only.
    /// Future profiles must be added through #24 rather than hidden hard-coded UI.
    static let builtInProfiles: [Self] = [.yujie]
}
