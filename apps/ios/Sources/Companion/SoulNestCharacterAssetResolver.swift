import Foundation

struct SoulNestResolvedCharacterAsset: Equatable, Sendable {
    let requestedState: SoulNestCharacterState
    let displayedState: SoulNestCharacterState
    let asset: SoulNestCharacterAsset
    let outfitID: String
    let sceneID: String
    let fallbackReason: SoulNestCharacterAssetFallbackReason?

    var usedFallback: Bool {
        self.fallbackReason != nil
    }
}

/// Why the resolver displayed an asset different from the originally requested one.
enum SoulNestCharacterAssetFallbackReason: Equatable, Sendable {
    case missingState(displayed: SoulNestCharacterState)
    case fileUnusable(SoulNestCharacterAssetFileStatus)
}

enum SoulNestCharacterAssetFileStatus: Equatable, Sendable {
    case missing
    case empty
    case unsupportedFormat
    case corrupt
    case usable
}

struct SoulNestCharacterAssetResolver: Sendable {
    enum ResolutionError: Error, Equatable, Sendable {
        case invalidPack
        case missingOutfit
        case missingScene
        case missingIdleFallback
        case accessScopeMismatch
        case noUsableFallback
    }

    func resolve(
        state: SoulNestCharacterState,
        outfitID: String? = nil,
        sceneID: String? = nil,
        from pack: SoulNestCharacterAssetPack,
        index: SoulNestCharacterAssetIndex? = nil,
        resourceStatus: (SoulNestCharacterAsset) -> SoulNestCharacterAssetFileStatus = { _ in .usable }) throws
        -> SoulNestResolvedCharacterAsset
    {
        guard pack.isValid else { throw ResolutionError.invalidPack }
        if let index, !index.serves(pack: pack) {
            throw ResolutionError.accessScopeMismatch
        }

        let selectedOutfitID = outfitID ?? pack.defaultOutfitID
        guard let outfit = pack.outfits.first(where: { $0.id == selectedOutfitID }) else {
            throw ResolutionError.missingOutfit
        }

        let selectedSceneID = sceneID ?? pack.defaultSceneID
        guard pack.scenes.contains(where: { $0.id == selectedSceneID }) else {
            throw ResolutionError.missingScene
        }

        guard let requestedAsset = outfit.asset(for: state) else {
            throw ResolutionError.missingIdleFallback
        }

        if resourceStatus(requestedAsset) == .usable {
            let reason: SoulNestCharacterAssetFallbackReason? = requestedAsset.state == state
                ? nil
                : .missingState(displayed: requestedAsset.state)
            return SoulNestResolvedCharacterAsset(
                requestedState: state,
                displayedState: requestedAsset.state,
                asset: requestedAsset,
                outfitID: selectedOutfitID,
                sceneID: selectedSceneID,
                fallbackReason: reason)
        }

        let requestedStatus = resourceStatus(requestedAsset)

        if requestedAsset.state != .idle,
           let idleAsset = outfit.asset(for: .idle),
           resourceStatus(idleAsset) == .usable
        {
            return SoulNestResolvedCharacterAsset(
                requestedState: state,
                displayedState: .idle,
                asset: idleAsset,
                outfitID: selectedOutfitID,
                sceneID: selectedSceneID,
                fallbackReason: .fileUnusable(requestedStatus))
        }

        if let placeholderIdle = SoulNestCharacterAssetPack.placeholderIdleAsset,
           resourceStatus(placeholderIdle) == .usable
        {
            return SoulNestResolvedCharacterAsset(
                requestedState: state,
                displayedState: .idle,
                asset: placeholderIdle,
                outfitID: selectedOutfitID,
                sceneID: selectedSceneID,
                fallbackReason: .fileUnusable(requestedStatus))
        }

        throw ResolutionError.noUsableFallback
    }
}
