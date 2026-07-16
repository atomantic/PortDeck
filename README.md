# PortDeck

<p align="center">
  <img src="PortDeck.png" width="200" alt="PortDeck app icon" />
</p>

PortDeck is the native iOS companion for [PortOS](https://github.com/atomantic/PortOS). The Xcode product and bundle identity remain `PortDeck`; the installed app is displayed as **PortOS**.

The app is now fleet-first. It connects directly to one or more PortOS instances over a Tailscale network, keeps each optional PortOS password in the iOS Keychain, and uses the live PortOS API instead of duplicating server capabilities in the app. Fleet profiles and passwords stay on the device by default; the user can opt into iCloud Keychain sync from Settings.

## What works now

- Add HTTP or HTTPS PortOS endpoints by MagicDNS name or Tailscale IP on port 5555
- Discover identity and auth posture through public `GET /api/system/health`
- Keep multiple instance profiles in SwiftData and choose the active capture/action target
- Store each PortOS password separately in Keychain and authenticate with password-only HTTP Basic
- Optionally sync fleet profiles and passwords between the user's devices through iCloud Keychain
- Inspect the active server's federation topology
- Add, connect, probe, sync, enable/disable, full-mirror, and remove federation peers
- Capture typed or on-device dictated text to Brain and Daily Log
- Load `/api/palette/manifest` and generate native forms for the server's palette-safe actions
- Handle older PortOS health payloads that predate `name` and `authRequired`

The previous Recall session-recording, audio-retention, analysis, and memory-extraction product has been removed. The new privacy boundary still permits a future explicit capture mode that uploads audio directly to the selected user-owned PortOS instance for processing; PortDeck does not require or operate a relay service.

## Test against a native PortOS instance

1. Make sure the iPhone and the PortOS machine are signed into the same Tailscale network.
2. Start or restart PortOS so the companion API changes from issue [#2678](https://github.com/atomantic/PortOS/issues/2678) are active.
3. Confirm the endpoint from another tailnet device:

   ```bash
   curl http://your-portos-host.tailnet.ts.net:5555/api/system/health
   # or, when PortOS TLS is enabled:
   curl https://your-portos-host.tailnet.ts.net:5555/api/system/health
   ```

   The response should include `instanceId`, `name`, `authRequired`, `scheme`, and `version`. PortDeck also supports the older response while a server is awaiting restart.

4. Generate the project and run it from Xcode:

   ```bash
   xcodegen generate
   open PortDeck.xcodeproj
   ```

5. In the Fleet tab, tap **Add an instance**, choose HTTP or HTTPS, enter the MagicDNS host or Tailscale IP, and keep port `5555` unless that instance is configured differently.
6. If PortOS reports that auth is enabled, enter that instance's PortOS password. It is written to this device's Keychain by default.
7. To share fleet profiles and passwords with another device on the same Apple Account, enable **Sync fleet and passwords** in Settings. This is optional and requires iCloud Keychain on each participating device.

For HTTP tailnet endpoints, PortDeck deliberately permits dynamic cleartext hosts through App Transport Security; iOS cannot express arbitrary user-entered MagicDNS names as static exception domains. For HTTPS, use a certificate trusted by iOS (the PortOS Tailscale certificate path). PortDeck does not bypass TLS validation for self-signed certificates.

## Development

`project.yml` is the source of truth for the generated project.

```bash
xcodegen generate

xcodebuild build \
  -project PortDeck.xcodeproj \
  -scheme PortDeck \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project PortDeck.xcodeproj \
  -scheme PortDeck \
  -only-testing:PortDeckTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

See [docs/PORTDECK_DESIGN.md](docs/PORTDECK_DESIGN.md) for the product structure and client architecture.

## Demo data and App Store screenshots

Add the `-demo-data` launch argument in Xcode to run PortDeck with a deterministic, in-memory fleet. Demo mode contains three connected PortOS instances, federation peers, capture text, and palette actions. It uses a simulated API transport and no-op credential/cloud stores, so it does not contact the network, Keychain, or iCloud.

The screenshot workflow is adapted from MortalLoom and automatically selects installed App Store-sized iPhone and iPad simulators:

```bash
./take_screenshots.sh
./take_screenshots.sh --iphone-only
./take_screenshots.sh --ipad-only
./take_screenshots.sh --screen 03_capture
```

It generates six English screenshots per device under `screenshots/en/`, fixes the simulator status bar at 9:41, and always launches the app with demo data. Screenshot output and transient configuration are gitignored.

## Product identity

- Xcode project and target: `PortDeck`
- Bundle ID: `net.shadowpuppet.PortDeck`
- URL scheme: `portdeck://`
- App Store display name: `PortOS`
- Minimum deployment target: iOS 17.0

## Deferred server-dependent layers

- MeatSpace POST recommendations, sessions, training prompts, and progress views
- Cross-instance POST progress reconciliation through the planned iCloud JSON import contract
- Push/reminder plumbing for POST training
- Direct audio upload once PortOS exposes a companion audio-ingest contract
- A future per-device PortOS token if the current single-password posture proves insufficient

## Deployment

`./deploy.sh` performs the MortalLoom-standard local TestFlight workflow. It requires a clean working tree and the App Store Connect credentials in `.env`, runs tests unless `--skip-tests` is supplied, increments the build with rollback on failure, makes a signed App Store archive, uploads through `altool --upload-package`, and commits, rebases, and pushes the successful build-number bump.
