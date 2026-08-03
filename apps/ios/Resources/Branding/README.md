# SoulNest iOS branding

SoulNest is the public-facing brand of this OpenClaw iOS fork. Internal OpenClaw
module, protocol, and build-setting names are intentionally retained where
renaming would increase upstream merge conflicts.

## Identifiers

- App: `com.wildenstudio.soulnest`
- Debug app: `com.wildenstudio.soulnest.debug`
- Share extension: `com.wildenstudio.soulnest.share`
- Activity widget: `com.wildenstudio.soulnest.activitywidget`
- Watch app: `com.wildenstudio.soulnest.watchkitapp`
- App group: `group.com.wildenstudio.soulnest.shared`
- URL schemes: `soulnest` and `soulnest-debug`

## Project generation

Use the SoulNest overlay instead of generating from the upstream spec alone:

```sh
cd apps/ios
./generate-soulnest-project.sh
```

The command renders the approved heart-and-nest design from the checked-in
Swift/CoreGraphics source, generates Release and Debug Apple Watch icon sizes
with macOS `sips`, and then invokes XcodeGen with the upstream project spec and
the small SoulNest branding overlay. Keeping brand overrides outside the large
upstream `project.yml` reduces merge conflicts during synchronization.

## App icon

The icon uses an original heart-and-nest composition approved for SoulNest. It
contains no third-party logo, OpenClaw mascot, text, or portrait.

The maintainable source of truth is:

```text
apps/ios/scripts/generate-soulnest-master-icons.swift
```

It renders opaque 1024×1024 Release and Debug PNG masters. Xcode 26's
single-size App Icon asset generates required iOS sizes, while
`generate-soulnest-icons.sh` derives the Apple Watch sizes. The Debug version
adds a cyan diamond badge without changing the core brand mark.

The source was created specifically for this repository and approved by the
repository owner. It is not imported from a third-party asset pack.

## Local signing

Do not commit Apple Team IDs, provisioning profiles, APNs keys, or certificates.
Place local values in `apps/ios/.local-signing.xcconfig` or
`apps/ios/LocalSigning.xcconfig`.
