# PortDeck

PortDeck is the iOS companion app for PortOS. `PortDeck` is the technical project and bundle identity; the App Store display name is `PortOS`.

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

Build the PortOS companion described in [issue #2678](https://github.com/atomantic/PortOS/issues/2678): multi-instance management first, followed by dictated daily logs, brain entries, palette-safe quick actions, and MeatSpace POST support. The recording implementation is a temporary legacy scaffold and does not define new product work.
