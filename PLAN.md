# PortDeck implementation plan

## Status: Re-scoping

PortDeck is the iOS companion for PortOS, as defined by [PortOS issue #2678](https://github.com/atomantic/PortOS/issues/2678). It is not a continuation of the previous session-recorder placeholder.

## Completed: product identity

- [x] Rename the Xcode project, targets, test bundles, source directories, and app entry point to `PortDeck`
- [x] Set the application bundle ID to `net.shadowpuppet.PortDeck`
- [x] Keep the App Store display name as `PortOS`
- [x] Replace the placeholder URL scheme with `portdeck://`
- [x] Update generated-project, CI, deployment, and documentation references

## Foundation

### Phase 1: Instance profiles

- [ ] SwiftData model for a PortOS instance: endpoint, instance ID, user label, health metadata, and connection state
- [ ] Add/edit/remove instance flows
- [ ] Pre-auth discovery using `GET /api/system/health`

### Phase 2: Authentication and transport

- [ ] Per-instance password storage in the iOS Keychain
- [ ] HTTP Basic authentication for password-protected instances
- [ ] Support passwordless PortOS installations and HTTP/HTTPS endpoints on port 5555
- [ ] Clear health, connection, and authentication error states

### Phase 3: Instance management

- [ ] Read and update the local instance profile through `/api/instances/*`
- [ ] Manage tailnet peers and their connection/sync state
- [ ] Establish an accessible multi-instance home screen

### Phase 4: Mobile actions

- [ ] Load the native action surface from `GET /api/palette/manifest`
- [ ] Dispatch palette-safe actions through `POST /api/palette/action/:id`
- [ ] Add dictated daily logs and brain captures

### Phase 5: MeatSpace POST companion features

- [ ] Display POST configuration, recommendations, sessions, and progress
- [ ] Record on-device training/testing progress
- [ ] Reconcile progress through the PortOS iCloud JSON integration once its import endpoint exists

## Upstream dependency

The PortOS-side contract in issue #2678 provides the public pre-auth health additions (`name`, `authRequired`) and documents the supported native-client API. PortDeck should handle the current health payload gracefully until those additions land.
