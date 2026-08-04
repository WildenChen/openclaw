import Foundation

/// Scoped index that isolates general assets from private ones. A general-scope
/// index rejects private packs and a private-scope index rejects general packs.
/// This is the boundary that keeps private character resources from leaking
/// into shared client surfaces.
struct SoulNestCharacterAssetIndex: Equatable, Sendable {
    let access: SoulNestCharacterAssetAccess
    private(set) var resources: [String: SoulNestCharacterAssetResource]
    private(set) var packIDs: Set<String>

    init(access: SoulNestCharacterAssetAccess) {
        self.access = access
        self.resources = [:]
        self.packIDs = []
    }

    var isValid: Bool {
        self.resources.values.allSatisfy(\.isValid)
    }

    /// Registers a pack and its manifest. Rejects mismatched access scope,
    /// invalid manifests, packs that disagree with their manifest, and duplicate
    /// resource ids or pack ids.
    @discardableResult
    mutating func register(
        _ pack: SoulNestCharacterAssetPack,
        manifest: SoulNestCharacterManifest) -> Bool
    {
        guard pack.accessScope == self.access,
              manifest.isValid,
              manifest.packID == pack.id,
              manifest.validates(pack)
        else {
            return false
        }

        let newIDs = Set(manifest.entries.map(\.id))
        guard newIDs.count == manifest.entries.count,
              newIDs.isDisjoint(with: self.resources.keys),
              !self.packIDs.contains(pack.id)
        else {
            return false
        }

        for entry in manifest.entries {
            guard let asset = self.packAsset(forID: entry.id, in: pack),
                  let resource = SoulNestCharacterAssetResource(asset: asset, manifestEntry: entry)
            else {
                return false
            }
            self.resources[resource.id] = resource
        }
        self.packIDs.insert(pack.id)
        return true
    }

    mutating func unregister(_ packID: String, manifest: SoulNestCharacterManifest) {
        guard self.packIDs.remove(packID) != nil else { return }
        for entry in manifest.entries {
            self.resources.removeValue(forKey: entry.id)
        }
    }

    func resource(for id: String) -> SoulNestCharacterAssetResource? {
        self.resources[id]
    }

    func serves(pack: SoulNestCharacterAssetPack) -> Bool {
        pack.accessScope == self.access
    }

    private func packAsset(forID id: String, in pack: SoulNestCharacterAssetPack) -> SoulNestCharacterAsset? {
        pack.allAssets.first(where: { $0.id == id })
    }
}
