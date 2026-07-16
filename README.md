# PortDeck

<p align="center">
  <img src="PortDeck.png" width="200" alt="PortDeck app icon" />
</p>

PortDeck is the iOS companion app for [PortOS](https://github.com/atomantic/PortOS). Its App Store display name is **PortOS**, while `PortDeck` is the product, target, and bundle identity used for development and distribution.

## Direction

PortDeck is being repurposed from a recording-app placeholder into the mobile companion described in [PortOS issue #2678](https://github.com/atomantic/PortOS/issues/2678). Its foundation is multi-instance management for PortOS installations reachable on a tailnet. Planned layers include:

- Discovering, identifying, labeling, and managing PortOS instances
- Secure per-instance authentication stored in the iOS Keychain
- Dictated daily logs, brain captures, and other palette-safe quick actions
- MeatSpace POST training and testing prompts
- iCloud JSON reconciliation for shared progress

The existing recorder implementation is retained temporarily as a migration scaffold; it does not define PortDeck's product scope.

## Product identity

- Xcode project and app target: `PortDeck`
- Bundle ID: `net.shadowpuppet.PortDeck`
- URL scheme: `portdeck://`
- App Store display name: `PortOS`
- Minimum deployment target: iOS 17.0

## Development

`project.yml` is the source of truth for the generated Xcode project.

```bash
# Generate Xcode project
brew install xcodegen
xcodegen generate

# Build
xcodebuild build \
  -project PortDeck.xcodeproj \
  -scheme PortDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test \
  -project PortDeck.xcodeproj \
  -scheme PortDeck \
  -only-testing:PortDeckTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

## Deployment

`./deploy.sh` performs the local TestFlight workflow. It requires the App Store Connect credentials described in `.env.example`.
