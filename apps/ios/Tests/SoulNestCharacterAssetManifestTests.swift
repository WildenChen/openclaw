import XCTest
@testable import OpenClaw

final class SoulNestCharacterAssetManifestTests: XCTestCase {
    func testPlaceholderManifestIsValidAndCoversPack() {
        let manifest = SoulNestCharacterManifest.yujiePlaceholder

        XCTAssertTrue(manifest.isValid)
        XCTAssertTrue(manifest.validates(SoulNestCharacterAssetPack.yujiePlaceholder))
    }

    func testManifestRejectsDuplicateEntryIDs() {
        let first = SoulNestCharacterManifestEntry(
            id: "yujie.default.idle",
            resourceName: "yujie-placeholder",
            fileExtension: "png",
            kind: .staticImage,
            byteSize: 0,
            sha256: nil,
            license: nil)
        let manifest = SoulNestCharacterManifest(
            version: 1,
            packID: "yujie.default",
            license: .placeholder,
            entries: [first, first])

        XCTAssertFalse(manifest.isValid)
    }

    func testManifestRejectsUnsupportedExtensionForKind() {
        let entry = SoulNestCharacterManifestEntry(
            id: "yujie.default.idle",
            resourceName: "yujie-placeholder",
            fileExtension: "gif",
            kind: .staticImage,
            byteSize: 0,
            sha256: nil,
            license: nil)
        let manifest = SoulNestCharacterManifest(
            version: 1,
            packID: "yujie.default",
            license: .placeholder,
            entries: [entry])

        XCTAssertFalse(manifest.isValid)
    }

    func testManifestRejectsMissingLicense() {
        let manifest = SoulNestCharacterManifest(
            version: 1,
            packID: "yujie.default",
            license: SoulNestAssetLicense(
                licenseName: " ",
                rightsOwner: "  ",
                sourceURL: nil,
                acquiredOn: nil,
                notes: nil,
                redistributable: true),
            entries: [])

        XCTAssertFalse(manifest.isValid)
    }

    func testResourceValidatesPackAssetAgreement() throws {
        let asset = SoulNestCharacterAssetPack.yujiePlaceholder.allAssets[0]
        let manifest = SoulNestCharacterManifest.yujiePlaceholder
        let entry = manifest.entry(for: asset)
        XCTAssertNotNil(entry)

        XCTAssertNotNil(try SoulNestCharacterAssetResource(asset: asset, manifestEntry: XCTUnwrap(entry)))
    }

    func testResourceRejectsAssetEntryMismatch() {
        let asset = SoulNestCharacterAssetPack.yujiePlaceholder.allAssets[0]
        let entry = SoulNestCharacterManifestEntry(
            id: asset.id,
            resourceName: "different-name",
            fileExtension: asset.fileExtension,
            kind: asset.kind,
            byteSize: 0,
            sha256: nil,
            license: nil)

        XCTAssertNil(SoulNestCharacterAssetResource(asset: asset, manifestEntry: entry))
    }

    func testStaticImageAndLoopingVideoHaveDistinctSupportedExtensions() {
        XCTAssertEqual(SoulNestCharacterAssetKind.staticImage.supportedFileExtensions, ["png", "jpg", "jpeg", "webp"])
        XCTAssertEqual(SoulNestCharacterAssetKind.loopingVideo.supportedFileExtensions, ["mp4", "mov", "m4v"])
        XCTAssertTrue(SoulNestCharacterAssetKind.staticImage.isSupported(fileExtension: "PNG"))
        XCTAssertFalse(SoulNestCharacterAssetKind.staticImage.isSupported(fileExtension: "gif"))
        XCTAssertTrue(SoulNestCharacterAssetKind.loopingVideo.isSupported(fileExtension: "mp4"))
        XCTAssertFalse(SoulNestCharacterAssetKind.loopingVideo.isSupported(fileExtension: "webm"))
    }

    func testAssetRejectsUnsupportedExtension() {
        let asset = SoulNestCharacterAsset(
            id: "yujie.default.idle",
            state: .idle,
            kind: .loopingVideo,
            resourceName: "yujie",
            fileExtension: "gif")
        XCTAssertFalse(asset.isValid)
    }

    func testPlaceholderLicenseIsValidAndRedistributable() {
        XCTAssertTrue(SoulNestAssetLicense.placeholder.isValid)
        XCTAssertTrue(SoulNestAssetLicense.placeholder.redistributable)
    }
}
