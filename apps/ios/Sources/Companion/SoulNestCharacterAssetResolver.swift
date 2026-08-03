import Foundation

struct SoulNestResolvedCharacterAsset: Equatable, Sendable {
    let requestedState: SoulNestCharacterState
    let displayedState: SoulNestCharacterState
    let asset: SoulNestCharacterAsset
    let outfitID: String
    let sceneID: String
    let usedFallback: Bool
}

struct SoulNestCharacterAssetResolver: Sendable {
    enum ResolutionError: Error, Equatable, Sendable {
        case invalidPack
        case missingOutfit
        case missingScene
        case missingIdleFallback
    }

    func resolve(
        state: SoulNestCharacterState,
        outfitID: String? = nil,
        sceneID: String? = nil,
        from pack: SoulNestCharacterAssetPack) throws -> SoulNestResolvedCharacterAsset
    {
        guard pack.isValid else { throw ResolutionError.invalidPack }

        let selectedOutfitID = outfitID ?? pack.defaultOutfitID
        guard let outfit = pack.outfits.first(where: { $0.id == selectedOutfitID }) else {
            throw ResolutionError.missingOutfit
        }

        let selectedSceneID = sceneID ?? pack.defaultSceneID
        guard pack.scenes.contains(where: { $0.id == selectedSceneID }) else {
            throw ResolutionError.missingScene
        }

        guard let asset = outfit.asset(for: state) else {
            throw ResolutionError.missingIdleFallback
        }

        return SoulNestResolvedCharacterAsset(
            requestedState: state,
            displayedState: asset.state,
            asset: asset,
            outfitID: selectedOutfitID,
            sceneID: selectedSceneID,
            usedFallback: asset.state != state)
    }
}
