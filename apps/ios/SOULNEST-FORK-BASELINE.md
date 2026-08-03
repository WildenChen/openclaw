# SoulNest iOS fork baseline

This document defines the minimum reproducible development baseline for the
SoulNest iOS fork while preserving a low-conflict path back to upstream
OpenClaw.

## Supported baseline

- Xcode project source: `apps/ios/project.yml`
- SoulNest-only XcodeGen overlay: `apps/ios/project.soulnest.yml`
- Generated Xcode project: `apps/ios/OpenClaw.xcodeproj` (not treated as the
  source of truth)
- Minimum iOS version and Xcode version remain inherited from upstream unless a
  dedicated compatibility issue changes them.
- Public app identity: `SoulNest`
- Release Bundle ID: `com.wildenstudio.soulnest`

Internal OpenClaw module, target, protocol, and build-setting names remain in
place unless a user-facing collision requires a narrow rename. This avoids a
large permanent diff against upstream.

## Clean checkout simulator build

Prerequisites on macOS:

- Xcode selected with `xcode-select`
- Homebrew
- Node.js
- XcodeGen

From the repository root:

```sh
brew install xcodegen
swift_tools="$(mktemp -d)/swift-tools"
./scripts/install-swift-tools.sh "$swift_tools"
export PATH="$swift_tools:$PATH"
./scripts/ios-write-version-xcconfig.sh
node scripts/ios-write-swift-filelist.mjs
cd apps/ios
./generate-soulnest-project.sh
xcodebuild \
  -project OpenClaw.xcodeproj \
  -scheme OpenClaw \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

The `SoulNest iOS` GitHub Actions workflow runs this unsigned Simulator build
without requiring Apple certificates, provisioning profiles, Gateway secrets,
or a real Gateway.

## Local device signing

Do not edit or commit personal signing values in `Signing.xcconfig`. Put local
values in the git-ignored `apps/ios/.local-signing.xcconfig` or
`apps/ios/LocalSigning.xcconfig`.

At minimum, a local device build needs an Apple Development Team and valid App
IDs for the main app and any enabled extensions. APNs and App Group capabilities
must be created in the same Apple Developer account before their end-to-end
features can be verified.

## Upstream synchronization

Configure the upstream remote once:

```sh
git remote add upstream https://github.com/openclaw/openclaw.git
git fetch upstream
```

For each update, use an isolated sync branch and a normal merge so published
history is not rewritten:

```sh
git switch main
git pull --ff-only origin main
git switch -c upstream-sync/YYYY-MM-DD
git merge --no-ff upstream/main
```

Resolve conflicts with these ownership rules:

1. Upstream owns `apps/ios/project.yml`, OpenClaw protocols, shared packages,
   Gateway behavior, and internal target/module names.
2. SoulNest owns `project.soulnest.yml`, `generate-soulnest-project.sh`, branding
   documentation, public identifiers, and SoulNest icon source assets.
3. Prefer extending the SoulNest overlay instead of editing large upstream files.
4. Never discard upstream security, protocol, signing, entitlement, or migration
   changes merely to preserve branding.
5. Open a pull request for the sync branch and require the SoulNest iOS workflow
   to pass before merging.

Rollback is a normal PR revert. Do not force-push `main` to undo an upstream
sync or branding change.

## Required real-device checks

The unsigned CI build cannot verify:

- Apple Team and provisioning configuration
- APNs registration and delivery
- App Group sharing among the app, Share Extension, widget, and Watch app
- URL Scheme handling on a physical device
- coexistence with the original OpenClaw installation
- Release and Debug icons on iPhone and Apple Watch

Record those results in the implementing pull request before closing the
corresponding issue.
