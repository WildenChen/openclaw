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
}
