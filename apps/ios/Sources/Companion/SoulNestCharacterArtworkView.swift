import SwiftUI
import UIKit

/// Resolves and renders the character artwork for a given state.
///
/// The resolver drives asset selection: a requested state with no usable file
/// falls back through idle to the placeholder, exactly as Issue #23 specified.
/// This view is only the final visual fallback when no asset bytes exist at all.
@MainActor
struct SoulNestCharacterArtworkView: View {
    let state: SoulNestCharacterState

    @State private var loader = SoulNestCharacterArtworkLoader()
    @State private var renderedImage: UIImage?

    var body: some View {
        Group {
            if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(OpenClawBrand.accent)
            }
        }
        .onAppear {
            self.reload()
        }
        .onChange(of: self.state) { _, _ in
            self.reload()
        }
    }

    private func reload() {
        if let resolved = self.loader.resolve(self.state),
           let image = self.loader.image(for: resolved.asset)
        {
            self.renderedImage = image
        } else {
            self.renderedImage = nil
        }
    }
}

/// Loads character artwork through the asset resolver, backed by the scoped
/// index and cache so resolution is observable and bounded. The placeholder
/// pack is registered at the general scope; real packs join the same index when
/// their manifests are committed.
@MainActor
struct SoulNestCharacterArtworkLoader {
    var index: SoulNestCharacterAssetIndex
    private(set) var cache: SoulNestCharacterAssetCache
    private let pack: SoulNestCharacterAssetPack
    private let resolver: SoulNestCharacterAssetResolver

    init(
        pack: SoulNestCharacterAssetPack = .yujiePlaceholder,
        manifest: SoulNestCharacterManifest = .yujiePlaceholder,
        cache: SoulNestCharacterAssetCache = SoulNestCharacterAssetCache(maxBytes: 16 * 1024 * 1024))
    {
        var index = SoulNestCharacterAssetIndex(access: .general)
        index.register(pack, manifest: manifest)
        self.index = index
        self.cache = cache
        self.pack = pack
        self.resolver = SoulNestCharacterAssetResolver()
    }

    /// Resolves `state` and records the displayed resource in the cache. Nil
    /// when no usable asset exists, which the view maps to its own fallback.
    mutating func resolve(_ state: SoulNestCharacterState) -> SoulNestResolvedCharacterAsset? {
        guard let resolved = try? self.resolver.resolve(
            state: state,
            from: self.pack,
            index: self.index,
            resourceStatus: { asset in
                UIImage(named: asset.resourceName) != nil ? .usable : .missing
            })
        else {
            return nil
        }
        if let resource = self.index.resource(for: resolved.asset.id) {
            self.cache.preload(resource: resource)
        }
        return resolved
    }

    func image(for asset: SoulNestCharacterAsset) -> UIImage? {
        UIImage(named: asset.resourceName)
    }
}
