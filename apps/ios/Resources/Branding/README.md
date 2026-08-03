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

The overlay keeps branding changes separate from the large upstream
`project.yml`, reducing merge conflicts during upstream synchronization.

## App icon

The icon uses an original heart-and-nest composition approved for SoulNest.
It contains no third-party logo, OpenClaw mascot, text, or portrait. The
repository stores an opaque 1024×1024 PNG for Release and a separately marked
Debug icon. Xcode 26's single-size App Icon asset generates required iOS sizes.

Source artwork was created specifically for this repository and approved by
the repository owner. It is not imported from a third-party asset pack.

## Local signing

Do not commit Apple Team IDs, provisioning profiles, APNs keys, or certificates.
Place local values in `apps/ios/.local-signing.xcconfig` or
`apps/ios/LocalSigning.xcconfig`.
