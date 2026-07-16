# PortDeck

PortDeck is the iOS companion app for PortOS. `PortDeck` is the project and bundle identity; the App Store display name is `PortOS`.

## Tech stack

- SwiftUI + SwiftData (iOS 17.0+)
- XcodeGen: `project.yml` is the source of truth, not the generated `.xcodeproj`
- Bundle ID: `net.shadowpuppet.PortDeck`; Team: `TYQ32QCF6K`

## Build commands

```bash
xcodegen generate

xcodebuild build -project PortDeck.xcodeproj -scheme PortDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

xcodebuild test -project PortDeck.xcodeproj -scheme PortDeck \
  -only-testing:PortDeckTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

./take_screenshots.sh --iphone-only
```

Use the `-demo-data` launch argument for a deterministic in-memory fleet with simulated API responses. `./take_screenshots.sh` enables it automatically.

## Product scope

The companion manages PortOS instances and later layers in daily-log dictation, brain entries, quick actions, and MeatSpace POST work. Use the native-client contract in PortOS issue #2678 as the integration reference. The legacy recording code is a temporary scaffold and should not drive new product work.
