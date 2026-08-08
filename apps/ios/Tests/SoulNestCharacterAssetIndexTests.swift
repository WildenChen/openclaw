import XCTest
@testable import OpenClaw

final class SoulNestCharacterAssetIndexTests: XCTestCase {
    private var privatePack: SoulNestCharacterAssetPack {
        SoulNestCharacterAssetPack(
            id: "yujie.private",
            agentProfileID: "yujie",
            outfits: SoulNestCharacterAssetPack.yujiePlaceholder.outfits,
            scenes: SoulNestCharacterAssetPack.yujiePlaceholder.scenes,
            defaultOutfitID: SoulNestCharacterAssetPack.yujiePlaceholder.defaultOutfitID,
            defaultSceneID: SoulNestCharacterAssetPack.yujiePlaceholder.defaultSceneID,
            accessScope: .privateOnly)
    }

    private var privateManifest: SoulNestCharacterManifest {
        SoulNestCharacterManifest(
            version: 1,
            packID: "yujie.private",
            license: .placeholder,
            entries: SoulNestCharacterAssetPack.yujiePlaceholder.allAssets.map { asset in
                SoulNestCharacterManifestEntry(
                    id: asset.id,
                    resourceName: asset.resourceName,
                    fileExtension: asset.fileExtension,
                    kind: asset.kind,
                    byteSize: 0,
                    sha256: nil,
                    license: nil)
            })
    }

    func testGeneralIndexRegistersGeneralPack() {
        var index = SoulNestCharacterAssetIndex(access: .general)
        XCTAssertTrue(index.register(SoulNestCharacterAssetPack.yujiePlaceholder, manifest: .yujiePlaceholder))
        XCTAssertEqual(index.packIDs, [SoulNestCharacterAssetPack.yujiePlaceholder.id])
        XCTAssertTrue(index.isValid)
    }

    func testGeneralIndexRejectsPrivatePack() {
        var index = SoulNestCharacterAssetIndex(access: .general)
        XCTAssertFalse(index.register(self.privatePack, manifest: self.privateManifest))
        XCTAssertTrue(index.packIDs.isEmpty)
        XCTAssertTrue(index.resources.isEmpty)
    }

    func testPrivateIndexRejectsGeneralPack() {
        var index = SoulNestCharacterAssetIndex(access: .privateOnly)
        XCTAssertFalse(index.register(SoulNestCharacterAssetPack.yujiePlaceholder, manifest: .yujiePlaceholder))
        XCTAssertTrue(index.packIDs.isEmpty)
    }

    func testPrivateIndexRegistersPrivatePack() {
        var index = SoulNestCharacterAssetIndex(access: .privateOnly)
        XCTAssertTrue(index.register(self.privatePack, manifest: self.privateManifest))
        XCTAssertEqual(index.packIDs, ["yujie.private"])
    }

    func testRegisterRejectsDuplicatePackID() {
        var index = SoulNestCharacterAssetIndex(access: .general)
        XCTAssertTrue(index.register(SoulNestCharacterAssetPack.yujiePlaceholder, manifest: .yujiePlaceholder))
        XCTAssertFalse(index.register(SoulNestCharacterAssetPack.yujiePlaceholder, manifest: .yujiePlaceholder))
        XCTAssertEqual(index.packIDs, [SoulNestCharacterAssetPack.yujiePlaceholder.id])
    }

    func testUnregisterRemovesResourcesAndPack() {
        var index = SoulNestCharacterAssetIndex(access: .general)
        XCTAssertTrue(index.register(SoulNestCharacterAssetPack.yujiePlaceholder, manifest: .yujiePlaceholder))

        index.unregister(SoulNestCharacterAssetPack.yujiePlaceholder.id, manifest: .yujiePlaceholder)

        XCTAssertTrue(index.packIDs.isEmpty)
        XCTAssertTrue(index.resources.isEmpty)
    }

    func testResolverRefusesScopeMismatch() {
        let generalIndex = SoulNestCharacterAssetIndex(access: .general)
        XCTAssertThrowsError(
            try SoulNestCharacterAssetResolver().resolve(
                state: .idle,
                from: self.privatePack,
                index: generalIndex))
        { error in
            XCTAssertEqual(
                error as? SoulNestCharacterAssetResolver.ResolutionError,
                .accessScopeMismatch)
        }
    }
}
