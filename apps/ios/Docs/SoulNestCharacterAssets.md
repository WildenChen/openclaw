# SoulNest character asset foundation

SoulNest treats character presentation assets as replaceable client UI resources. They are not part of the OpenClaw agent personality, durable memory, conversation history, or media attachment library.

## Ownership boundary

- OpenClaw `yujie` remains authoritative for identity, SOUL, memory, tools, schedules, and model output.
- `SoulNestCharacterAssetPack` contains only non-sensitive client presentation metadata.
- `SoulNestCharacterManifest` catalogs the pack's resources with size, hash, and license metadata; it must validate before a pack can render.
- Conversation images and generated selfies belong to the media flow tracked by #14, not this asset pack.
- Private or licensed character resources must not be committed unless their redistribution rights are recorded in `SoulNestAssetLicense`.

## Required states

The first release supports these state values:

- `idle`
- `thinking`
- `listening`
- `talking`
- `offline`

A pack may provide static image resources (PNG/JPG/JPEG/WEBP) or short looping video resources (MP4/MOV/M4V). When a requested state is missing, the resolver safely falls back to the outfit's `idle` asset so character rendering cannot block text chat.

## Asset validation

- `SoulNestCharacterAssetKind` declares the supported extension set per kind so unexpected containers never silently render.
- `SoulNestCharacterAssetFileValidator` reports `missing`, `empty`, `unsupportedFormat`, `corrupt`, or `usable` by checking file existence, size, extension, and a small magic-byte header. Anything outside `usable` is treated as a fallback signal: the resolver tries the outfit's idle asset next, then the placeholder pack's idle asset, then errors with `.noUsableFallback`.
- The placeholder fallback uses `SoulNestCharacterAssetPack.placeholderIdleAsset`, which is a generic static-image placeholder. Real Yujie artwork must never be committed under the placeholder id.

## Pack completeness

- `SoulNestCharacterAssetPack.isValid` is the structural contract (defaults present, idle present, all assets valid).
- `SoulNestCharacterAssetPack.isComplete` is the strict completeness check: every outfit covers every required state.
- `SoulNestCharacterAssetPack.missingStates(for:)` enumerates the gap so callers can decide whether to fix the asset import or accept idle fallbacks.

## Cache and index isolation

- `SoulNestCharacterAssetCache` is the data-layer contract for preloaded resources: bounded byte budget, LRU eviction, `preload`, `touch`, `evictLeastRecentlyUsed`, `clear`. Actual byte loading stays in the rendering layer.
- `SoulNestCharacterAssetIndex` enforces the general-vs-private boundary. `SoulNestCharacterAssetAccess` (`general` / `privateOnly`) is set on each pack; a general index rejects private packs and vice versa. The resolver refuses packs whose scope does not match the supplied index with `.accessScopeMismatch`.

## Current placeholder

`SoulNestCharacterAssetPack.yujiePlaceholder` defines the metadata contract and points all states at a placeholder resource name. `SoulNestCharacterManifest.yujiePlaceholder` declares those resources with `SoulNestAssetLicense.placeholder`. The actual approved Yujie artwork is intentionally not committed by this change. A later asset import must include provenance and redistribution notes.

## Deliberately deferred

- Neural portrait animation, phoneme lip sync, Live2D, and 3D belong to #18.
- Character home-screen rendering and animation playback belong to #7.
- Talk Mode state wiring belongs to #13.
- Private asset protection work product belongs to #11 and #20; the index isolation boundary here keeps the seam ready for those changes.
