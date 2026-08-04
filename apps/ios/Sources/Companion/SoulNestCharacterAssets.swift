import Foundation

enum SoulNestCharacterState: String, Codable, CaseIterable, Sendable {
    case idle
    case thinking
    case listening
    case talking
    case offline
}

enum SoulNestCharacterAssetKind: String, Codable, Sendable {
    case staticImage
    case loopingVideo

    /// Extensions the resolver accepts for each kind. Kept narrow so unexpected
    /// containers fall back instead of being trusted to render correctly.
    var supportedFileExtensions: [String] {
        switch self {
        case .staticImage:
            ["png", "jpg", "jpeg", "webp"]
        case .loopingVideo:
            ["mp4", "mov", "m4v"]
        }
    }

    func isSupported(fileExtension: String) -> Bool {
        self.supportedFileExtensions.contains(fileExtension.lowercased())
    }
}

/// Access scope for character asset packs and indexes. Private assets never
/// resolve through the general index; general assets never resolve through a
/// private index. This boundary prevents private artwork from leaking into
/// shared client surfaces.
enum SoulNestCharacterAssetAccess: String, Codable, Sendable {
    case general
    case privateOnly
}

struct SoulNestCharacterAsset: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let state: SoulNestCharacterState
    let kind: SoulNestCharacterAssetKind
    let resourceName: String
    let fileExtension: String

    var isValid: Bool {
        !self.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.resourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            self.kind.isSupported(fileExtension: self.fileExtension)
    }
}

struct SoulNestCharacterOutfit: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var assets: [SoulNestCharacterAsset]

    func asset(for state: SoulNestCharacterState) -> SoulNestCharacterAsset? {
        self.assets.first(where: { $0.state == state }) ?? self.assets.first(where: { $0.state == .idle })
    }
}

struct SoulNestCharacterScene: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var backgroundResourceName: String?
}

struct SoulNestCharacterAssetPack: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let agentProfileID: String
    var outfits: [SoulNestCharacterOutfit]
    var scenes: [SoulNestCharacterScene]
    var defaultOutfitID: String
    var defaultSceneID: String
    var accessScope: SoulNestCharacterAssetAccess

    init(
        id: String,
        agentProfileID: String,
        outfits: [SoulNestCharacterOutfit],
        scenes: [SoulNestCharacterScene],
        defaultOutfitID: String,
        defaultSceneID: String,
        accessScope: SoulNestCharacterAssetAccess = .general)
    {
        self.id = id
        self.agentProfileID = agentProfileID
        self.outfits = outfits
        self.scenes = scenes
        self.defaultOutfitID = defaultOutfitID
        self.defaultSceneID = defaultSceneID
        self.accessScope = accessScope
    }

    var isValid: Bool {
        guard !self.id.isEmpty,
              !self.agentProfileID.isEmpty,
              self.outfits.contains(where: { $0.id == self.defaultOutfitID }),
              self.scenes.contains(where: { $0.id == self.defaultSceneID })
        else {
            return false
        }

        return self.outfits.allSatisfy { outfit in
            !outfit.id.isEmpty &&
                !outfit.displayName.isEmpty &&
                outfit.assets.allSatisfy(\.isValid) &&
                outfit.asset(for: .idle) != nil
        }
    }

    /// Strict completeness: every outfit provides every required state. A pack
    /// may still be structurally valid and resolvable via the idle fallback when
    /// incomplete; this is the explicit completeness gate.
    var isComplete: Bool {
        self.outfits.allSatisfy { outfit in
            self.missingStates(for: outfit.id).isEmpty
        }
    }

    /// States `outfitID` cannot render directly and would fall back to idle.
    func missingStates(for outfitID: String) -> Set<SoulNestCharacterState> {
        guard let outfit = self.outfits.first(where: { $0.id == outfitID }) else {
            return Set(SoulNestCharacterState.allCases)
        }
        let present = Set(outfit.assets.map(\.state))
        return Set(SoulNestCharacterState.allCases).subtracting(present)
    }

    var allAssets: [SoulNestCharacterAsset] {
        self.outfits.flatMap(\.assets)
    }

    static let yujiePlaceholder = Self(
        id: "yujie.default",
        agentProfileID: "yujie",
        outfits: [
            SoulNestCharacterOutfit(
                id: "default",
                displayName: "預設",
                assets: SoulNestCharacterState.allCases.map { state in
                    SoulNestCharacterAsset(
                        id: "yujie.default.\(state.rawValue)",
                        state: state,
                        kind: .staticImage,
                        resourceName: "yujie-placeholder",
                        fileExtension: "png")
                }),
        ],
        scenes: [
            SoulNestCharacterScene(
                id: "default",
                displayName: "預設",
                backgroundResourceName: nil),
        ],
        defaultOutfitID: "default",
        defaultSceneID: "default")
}

extension SoulNestCharacterAssetPack {
    /// The placeholder idle asset used as the ultimate fallback when every other
    /// candidate is unusable. Exposed for the resolver and tests.
    static var placeholderIdleAsset: SoulNestCharacterAsset? {
        SoulNestCharacterAssetPack.yujiePlaceholder
            .outfits.first { $0.id == SoulNestCharacterAssetPack.yujiePlaceholder.defaultOutfitID }?
            .asset(for: .idle)
    }
}
