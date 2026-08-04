import Foundation

/// License and provenance metadata for character artwork.
///
/// A resource may only be bundled when its redistribution rights are recorded
/// here. Placeholder fixtures use a placeholder license that carries no real
/// likeness.
struct SoulNestAssetLicense: Codable, Equatable, Sendable {
    var licenseName: String
    var rightsOwner: String
    var sourceURL: URL?
    var acquiredOn: String?
    var notes: String?
    var redistributable: Bool

    var isValid: Bool {
        !self.licenseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.rightsOwner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let placeholder = Self(
        licenseName: "Placeholder (no artwork)",
        rightsOwner: "SoulNest",
        sourceURL: nil,
        acquiredOn: nil,
        notes: "Procedural placeholder metadata only; no likeness committed.",
        redistributable: true)
}

/// Cataloged character artwork resource with size, hash, and optional per-entry
/// license override. Bytes and hash are absent for placeholder entries that
/// have no committed file; the validator treats those as unusable and falls back.
struct SoulNestCharacterAssetResource: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: SoulNestCharacterAssetKind
    let resourceName: String
    let fileExtension: String
    let byteSize: Int
    let sha256: String?
    let license: SoulNestAssetLicense?

    var fileName: String {
        "\(self.resourceName).\(self.fileExtension)"
    }

    var isStaticImage: Bool {
        self.kind == .staticImage
    }

    var isLoopingVideo: Bool {
        self.kind == .loopingVideo
    }

    var isValid: Bool {
        self.kind.isSupported(fileExtension: self.fileExtension) &&
            self.byteSize >= 0 &&
            !self.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.resourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: String,
        kind: SoulNestCharacterAssetKind,
        resourceName: String,
        fileExtension: String,
        byteSize: Int,
        sha256: String? = nil,
        license: SoulNestAssetLicense? = nil)
    {
        self.id = id
        self.kind = kind
        self.resourceName = resourceName
        self.fileExtension = fileExtension
        self.byteSize = byteSize
        self.sha256 = sha256
        self.license = license
    }

    /// Builds a resource from a pack asset plus its manifest metadata. Returns
    /// nil when the metadata disagrees with the asset (id, kind, file, extension),
    /// which keeps pack→manifest binding explicit.
    init?(asset: SoulNestCharacterAsset, manifestEntry: SoulNestCharacterManifestEntry) {
        guard asset.id == manifestEntry.id,
              asset.kind == manifestEntry.kind,
              asset.resourceName == manifestEntry.resourceName,
              asset.fileExtension == manifestEntry.fileExtension
        else {
            return nil
        }

        self.init(
            id: asset.id,
            kind: asset.kind,
            resourceName: asset.resourceName,
            fileExtension: asset.fileExtension,
            byteSize: manifestEntry.byteSize,
            sha256: manifestEntry.sha256,
            license: manifestEntry.license)
    }
}

struct SoulNestCharacterManifestEntry: Codable, Equatable, Sendable {
    let id: String
    let resourceName: String
    let fileExtension: String
    let kind: SoulNestCharacterAssetKind
    let byteSize: Int
    let sha256: String?
    let license: SoulNestAssetLicense?

    var isValid: Bool {
        self.kind.isSupported(fileExtension: self.fileExtension) &&
            self.byteSize >= 0 &&
            !self.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.resourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !self.fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The pack's catalog of resources with provenance metadata. Manifests are
/// validated before binding to a pack so rendering cannot draw from a half-built
/// resource list.
struct SoulNestCharacterManifest: Codable, Equatable, Sendable {
    var version: Int
    var packID: String
    var license: SoulNestAssetLicense
    var entries: [SoulNestCharacterManifestEntry]

    var isValid: Bool {
        guard self.version >= 1,
              !self.packID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              self.license.isValid,
              !self.entries.isEmpty,
              self.entries.allSatisfy(\.isValid)
        else {
            return false
        }

        return Set(self.entries.map(\.id)).count == self.entries.count
    }

    /// True when manifest and pack share the same id and have a one-to-one asset
    /// mapping (no orphan entries on either side).
    func validates(_ pack: SoulNestCharacterAssetPack) -> Bool {
        guard self.packID == pack.id else { return false }
        let packIDs = Set(pack.allAssets.map(\.id))
        let manifestIDs = Set(self.entries.map(\.id))
        return packIDs == manifestIDs
    }

    func entry(for asset: SoulNestCharacterAsset) -> SoulNestCharacterManifestEntry? {
        self.entries.first(where: { $0.id == asset.id })
    }

    static let yujiePlaceholder = Self(
        version: 1,
        packID: SoulNestCharacterAssetPack.yujiePlaceholder.id,
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
