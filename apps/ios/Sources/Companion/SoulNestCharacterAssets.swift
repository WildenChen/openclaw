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
            !self.fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
