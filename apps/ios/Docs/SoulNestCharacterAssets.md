# SoulNest character asset foundation

SoulNest treats character presentation assets as replaceable client UI resources. They are not part of the OpenClaw agent personality, durable memory, conversation history, or media attachment library.

## Ownership boundary

- OpenClaw `yujie` remains authoritative for identity, SOUL, memory, tools, schedules, and model output.
- `SoulNestCharacterAssetPack` contains only non-sensitive client presentation metadata.
- Conversation images and generated selfies belong to the media flow tracked by #14, not this asset pack.
- Private or licensed character resources must not be committed unless their redistribution rights are recorded.

## Required states

The first release supports these state values:

- `idle`
- `thinking`
- `listening`
- `talking`
- `offline`

A pack may provide static PNG resources or short looping video resources. When a requested state is missing, the resolver safely falls back to the outfit's `idle` asset so character rendering cannot block text chat.

## Current placeholder

`SoulNestCharacterAssetPack.yujiePlaceholder` defines the metadata contract and points all states at a placeholder resource name. The actual approved Yujie artwork is intentionally not committed by this change. A later asset import must include provenance and redistribution notes.

## Deliberately deferred

- Neural portrait animation, phoneme lip sync, Live2D, and 3D belong to #18.
- Character home-screen rendering and animation playback belong to #7.
- Talk Mode state wiring belongs to #13.
- Private asset protection belongs to #11 and #20.
