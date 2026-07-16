# PortDeck implementation plan

## Status: Fleet foundation implemented

PortDeck is the iOS companion for PortOS defined by [PortOS issue #2678](https://github.com/atomantic/PortOS/issues/2678). It is no longer a session-recorder product.

## Completed: product identity and redesign

- [x] Keep `PortDeck` as the technical project/bundle identity and `PortOS` as the App Store display name
- [x] Replace the Recall information architecture, models, services, and app icon
- [x] Establish Fleet, Capture, Actions, and Settings as the primary native surfaces
- [x] Keep `project.yml` as the generated Xcode project source of truth

## Completed: instance foundation

- [x] SwiftData model for endpoint, stable instance ID, local label, health metadata, and connection state
- [x] Add/edit/remove local instance connections
- [x] Pre-auth discovery through `GET /api/system/health`
- [x] Backward compatibility for the health payload before the companion fields land or a server restarts
- [x] Clear online, offline, checking, and password-required states

## Completed: authentication and transport

- [x] Per-instance password storage in the iOS Keychain
- [x] Optional fleet-profile and password sync through iCloud Keychain, disabled by default
- [x] Password-only HTTP Basic authentication for protected PortOS instances
- [x] Passwordless tailnet-trust connections
- [x] User-entered HTTP and HTTPS endpoints with port 5555 defaults
- [x] HTTP ATS support for dynamic MagicDNS/Tailscale hosts without weakening TLS validation

## Completed: federation management

- [x] Read self identity, peers, and sync state from `/api/instances`
- [x] Rename the remote PortOS identity through `PUT /api/instances/self`
- [x] Add and remove peers
- [x] Make peer relationships mutual, probe reachability, and trigger sync
- [x] Enable/disable peers and toggle full-mirror mode
- [ ] Add native per-category selective-sync controls
- [ ] Resolve a saved MagicDNS fleet entry to its Tailscale IPv4 automatically when adding it as a server peer

## Completed: mobile capture and actions

- [x] Brain capture through the palette bridge
- [x] Typed Daily Log append through the structured direct route
- [x] On-device dictated Daily Log append through `daily_log_append`
- [x] Load the live native action surface from `GET /api/palette/manifest`
- [x] Generate fields from each action's JSON parameter schema
- [x] Confirm actions PortOS marks destructive
- [x] Keep current dictation on-device and document direct-to-PortOS audio as an allowed future opt-in transport
- [ ] Upload audio directly to the active PortOS instance once its companion ingest endpoint exists

## Next: MeatSpace POST companion

- [ ] Display POST configuration, recommendations, sessions, stats, and progress per instance
- [ ] Add phone-first POST training/testing sessions
- [ ] Add local reminders while push-notification plumbing is pending
- [ ] Reconcile progress through iCloud JSON once the PortOS import endpoint exists

## Hardening before distribution

- [x] Add deterministic, offline demo data for App Store presentation
- [x] Add automated iPhone and iPad App Store screenshot capture
- [x] Align local TestFlight deployment with the MortalLoom release workflow
- [x] Exercise the full UI and screenshot flows on an updated CoreSimulator runtime
- [ ] Add accessibility and Dynamic Type snapshots for the four primary surfaces
- [ ] Test trusted Tailscale HTTPS and HTTP against multiple physical devices
- [ ] Decide whether the broad dynamic-host ATS allowance is acceptable for App Review or requires an HTTPS-only distribution posture
