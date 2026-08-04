import XCTest
@testable import OpenClaw

final class SoulNestCharacterAssetTests: XCTestCase {
    func testPlaceholderPackProvidesAllRequiredStates() throws {
        let pack = SoulNestCharacterAssetPack.yujiePlaceholder
        XCTAssertTrue(pack.isValid)

        let resolver = SoulNestCharacterAssetResolver()
        for state in SoulNestCharacterState.allCases {
            let result = try resolver.resolve(state: state, from: pack)
            XCTAssertEqual(result.requestedState, state)
            XCTAssertEqual(result.displayedState, state)
            XCTAssertFalse(result.usedFallback)
        }
    }

    func testMissingStateFallsBackToIdleWithoutBlockingChat() throws {
        let idle = SoulNestCharacterAsset(
            id: "idle",
            state: .idle,
            kind: .staticImage,
            resourceName: "idle",
            fileExtension: "png")
        let pack = SoulNestCharacterAssetPack(
            id: "test",
            agentProfileID: "yujie",
            outfits: [
                SoulNestCharacterOutfit(
                    id: "default",
                    displayName: "Default",
                    assets: [idle]),
            ],
            scenes: [
                SoulNestCharacterScene(
                    id: "default",
                    displayName: "Default",
                    backgroundResourceName: nil),
            ],
            defaultOutfitID: "default",
            defaultSceneID: "default")

        let result = try SoulNestCharacterAssetResolver().resolve(state: .talking, from: pack)

        XCTAssertEqual(result.requestedState, .talking)
        XCTAssertEqual(result.displayedState, .idle)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.asset, idle)
    }

    func testInvalidOutfitSelectionFailsExplicitly() {
        XCTAssertThrowsError(
            try SoulNestCharacterAssetResolver().resolve(
                state: .idle,
                outfitID: "missing",
                from: .yujiePlaceholder))
        { error in
            XCTAssertEqual(error as? SoulNestCharacterAssetResolver.ResolutionError, .missingOutfit)
        }
    }

    func testPackRequiresDefaultOutfitSceneAndIdleAsset() {
        let invalid = SoulNestCharacterAssetPack(
            id: "invalid",
            agentProfileID: "yujie",
            outfits: [],
            scenes: [],
            defaultOutfitID: "missing",
            defaultSceneID: "missing")

        XCTAssertFalse(invalid.isValid)
        XCTAssertThrowsError(
            try SoulNestCharacterAssetResolver().resolve(state: .idle, from: invalid))
    }

    func testPlaceholderPackIsComplete() {
        XCTAssertTrue(SoulNestCharacterAssetPack.yujiePlaceholder.isComplete)
        XCTAssertEqual(SoulNestCharacterAssetPack.yujiePlaceholder.missingStates(for: "default"), [])
    }

    func testPackMissingStatesIsIncompleteButStillResolvable() throws {
        let idle = SoulNestCharacterAsset(
            id: "idle",
            state: .idle,
            kind: .staticImage,
            resourceName: "idle",
            fileExtension: "png")
        let pack = SoulNestCharacterAssetPack(
            id: "partial",
            agentProfileID: "yujie",
            outfits: [
                SoulNestCharacterOutfit(id: "default", displayName: "Default", assets: [idle]),
            ],
            scenes: [
                SoulNestCharacterScene(id: "default", displayName: "Default", backgroundResourceName: nil),
            ],
            defaultOutfitID: "default",
            defaultSceneID: "default")

        XCTAssertTrue(pack.isValid)
        XCTAssertFalse(pack.isComplete)
        XCTAssertEqual(pack.missingStates(for: "default").count, SoulNestCharacterState.allCases.count - 1)

        let result = try SoulNestCharacterAssetResolver().resolve(state: .talking, from: pack)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.displayedState, .idle)
    }

    func testResolverFallsBackToIdleAssetWhenRequestedFileUnusable() throws {
        let idle = SoulNestCharacterAsset(
            id: "idle",
            state: .idle,
            kind: .staticImage,
            resourceName: "idle",
            fileExtension: "png")
        let talking = SoulNestCharacterAsset(
            id: "talking",
            state: .talking,
            kind: .staticImage,
            resourceName: "talking",
            fileExtension: "png")
        let pack = SoulNestCharacterAssetPack(
            id: "partial-valid",
            agentProfileID: "yujie",
            outfits: [
                SoulNestCharacterOutfit(id: "default", displayName: "Default", assets: [idle, talking]),
            ],
            scenes: [
                SoulNestCharacterScene(id: "default", displayName: "Default", backgroundResourceName: nil),
            ],
            defaultOutfitID: "default",
            defaultSceneID: "default")

        let result = try SoulNestCharacterAssetResolver().resolve(
            state: .talking,
            from: pack,
            resourceStatus: { asset in asset.state == .talking ? .corrupt : .usable })

        XCTAssertEqual(result.requestedState, .talking)
        XCTAssertEqual(result.displayedState, .idle)
        XCTAssertEqual(result.asset.state, .idle)
        if case let .fileUnusable(status) = result.fallbackReason {
            XCTAssertEqual(status, .corrupt)
        } else {
            XCTFail("expected fileUnusable fallback reason, got \(String(describing: result.fallbackReason))")
        }
    }

    func testResolverFallsBackToPlaceholderWhenEveryAssetUnusable() throws {
        let idle = SoulNestCharacterAsset(
            id: "idle",
            state: .idle,
            kind: .staticImage,
            resourceName: "idle",
            fileExtension: "png")
        let pack = SoulNestCharacterAssetPack(
            id: "all-unusable",
            agentProfileID: "yujie",
            outfits: [
                SoulNestCharacterOutfit(id: "default", displayName: "Default", assets: [idle]),
            ],
            scenes: [
                SoulNestCharacterScene(id: "default", displayName: "Default", backgroundResourceName: nil),
            ],
            defaultOutfitID: "default",
            defaultSceneID: "default")

        let placeholder = SoulNestCharacterAssetPack.placeholderIdleAsset
        let result = try SoulNestCharacterAssetResolver().resolve(
            state: .thinking,
            from: pack,
            resourceStatus: { asset in
                if asset.id == placeholder?.id { return .usable }
                return .missing
            })

        XCTAssertEqual(result.asset.id, placeholder?.id)
        if case let .fileUnusable(status) = result.fallbackReason {
            XCTAssertEqual(status, .missing)
        } else {
            XCTFail("expected fileUnusable fallback reason, got \(String(describing: result.fallbackReason))")
        }
    }

    func testResolverThrowsWhenNoUsableFallbackExists() {
        let idle = SoulNestCharacterAsset(
            id: "idle",
            state: .idle,
            kind: .staticImage,
            resourceName: "idle",
            fileExtension: "png")
        let pack = SoulNestCharacterAssetPack(
            id: "all-unusable",
            agentProfileID: "yujie",
            outfits: [
                SoulNestCharacterOutfit(id: "default", displayName: "Default", assets: [idle]),
            ],
            scenes: [
                SoulNestCharacterScene(id: "default", displayName: "Default", backgroundResourceName: nil),
            ],
            defaultOutfitID: "default",
            defaultSceneID: "default")

        XCTAssertThrowsError(
            try SoulNestCharacterAssetResolver().resolve(
                state: .idle,
                from: pack,
                resourceStatus: { _ in .missing }))
        { error in
            XCTAssertEqual(
                error as? SoulNestCharacterAssetResolver.ResolutionError,
                .noUsableFallback)
        }
    }
}
