# PortDeck product and client design

## Product stance

PortDeck is the pocket control surface for a user's private PortOS fleet. The phone is not another PortOS web client and not a recording archive. It does the jobs a phone is unusually good at:

- remembering several tailnet-reachable PortOS homes;
- choosing exactly where a capture or action runs;
- accepting fast typed or dictated input;
- exposing small, safe native forms for PortOS actions;
- prompting future MeatSpace POST work.

The server remains authoritative for federation, action definitions, Brain data, Daily Logs, and POST progress. PortDeck stores connection metadata, the active-target preference, and credentials—not a competing copy of PortOS content. Those connection profiles and credentials are local by default and may be synchronized through iCloud Keychain only when the user opts in.

## Information architecture

| Surface | Job | Source of truth |
| --- | --- | --- |
| Fleet | Connect, identify, select, and manage PortOS instances and federation peers | SwiftData profiles + `/api/system/health` + `/api/instances` |
| Capture | Send text or device-transcribed speech to Brain or Daily Log | `/api/palette/action/*` + `/api/brain/daily-log/*` |
| Actions | Render and invoke the current palette-safe server capability set | `/api/palette/manifest` |
| Settings | Control optional iCloud sync and explain transport, privacy, and project identity | Local preference + iCloud Keychain |

The selected Fleet instance is the explicit destination for both Capture and Actions. PortDeck never fans a mutation out to every server implicitly.

## Connection lifecycle

1. Normalize the user-entered HTTP/HTTPS endpoint and default it to port 5555.
2. Call public `GET /api/system/health` without credentials.
3. Present the server's stable identity, display name, version, scheme, and auth requirement.
4. When required, collect the single PortOS password and validate it against `GET /api/instances`.
5. Save the connection profile in SwiftData and the password under the profile's local UUID in Keychain.
6. Refresh health whenever Fleet opens or the user pulls to refresh; treat a gated `401` as authoritative even if an older health response omitted `authRequired`.

When iCloud sync is enabled, PortDeck writes a compact fleet-profile index and each per-instance password as separate synchronizable Keychain items. SwiftData remains the device-local working set. Disabling sync copies available passwords back into device-only Keychain items and stops profile synchronization; it does not erase the user's other iCloud Keychain copies.

## Security boundaries

- A native `URLSession` sends no browser `Origin`, matching the PortOS native-client contract and its CSRF posture.
- HTTP Basic uses `base64(":" + password)` because PortOS is password-only.
- Passwords are never persisted in SwiftData, UserDefaults, logs, or app state restoration. They use device-only Keychain items by default and synchronizable iCloud Keychain items only after explicit opt-in.
- Fleet metadata may use an app-scoped synchronizable Keychain item after the same opt-in. Brain entries, Daily Logs, action payloads, and POST content are never included in that fleet sync.
- HTTP exists only to support the documented private-tailnet deployment shape. HTTPS still uses normal system trust; self-signed trust bypasses are intentionally absent.
- Peer credentials entered while creating a federation peer are sent to the selected PortOS server's existing federation credential store and are not retained by PortDeck.

## Audio boundary

Current dictation is transcribed on the phone and PortDeck sends text to the selected PortOS instance. A future audio capture mode may upload microphone audio directly to that selected, user-owned instance when the user explicitly starts or enables it. The client design does not require a PortDeck-operated server, third-party transcription service, or permanent local recording archive. The PortOS audio-ingest route, retention controls, and deletion semantics remain server-contract work.

## Adaptive action UI

The Actions tab deliberately consumes the live palette manifest instead of maintaining a hard-coded action list. PortDeck maps the manifest's JSON-schema subset as follows:

- `string` -> native text field or enum picker;
- `integer` / `number` -> numeric keyboard and client-side conversion;
- `boolean` -> toggle;
- required parameters -> validation before dispatch;
- `destructive: true` -> explicit confirmation.

This keeps safe new PortOS actions discoverable without an app release while preserving the server's whitelist as the authority.

### Readers vs. run forms

The manifest does not label actions read vs. write, so PortDeck infers it from the id. An action becomes a *reader* — a page that fetches the moment it opens — only when one of its id components is a read verb (`list`, `recent`, `search`, `status`, `today`, `now`, `digest`, …), none is a write verb (`set`, `start`, `sync`, `backup`, `mark`, `capture`, …), it declares no required parameters, and PortOS did not flag it destructive. Every condition earns its place: `timer_set` takes no required parameters and still creates a timer; `backup_now` and `feeds_mark_read` read half like queries; and generative actions such as `ui_ask` and `image_generate` must never spend a provider call because someone opened a page. Ids neither list recognizes fail closed to a manual Run form.

Because PortOS installs update independently of App Store releases, a new server-side read tool whose id misses the verb list degrades to a run form rather than misbehaving. A server-declared `readOnly` flag on `PALETTE_ACTIONS` would remove the guessing entirely; the heuristic should become the older-peer fallback once that exists.

Reader pages render the payload rather than only its `summary`: the primary collection in the response (`items`, `hits`, `goals`, `events`, …) becomes rows, long-form strings become passages, remaining scalars become facts, and the raw JSON stays one disclosure away. Their parameters move into a collapsed Options panel, and the result window widens either by editing the page-size parameter (`limit`, `count`, `max`) or by scrolling to the end of the list. PortOS clamps its own maximum, so a page that returns no more rows than the last one ends the list.

## Visual system

The interface uses system typography, grouped adaptive surfaces, and a restrained cyan-to-violet identity on a system background. Cyan represents reachability and active routing; violet represents invoked capabilities. Green, amber, and red are reserved for state. The icon depicts one control port connected to three server nodes, replacing the old brain/recording identity.

## Deferred architecture

MeatSpace POST data stays instance-local until PortOS ships a reconciliation path. PortDeck should read every configured instance directly until then. The optional Keychain fleet sync is limited to connection profiles and credentials; it is not a content-sync channel. When the planned iCloud JSON import contract exists, add a separate reconciliation service rather than making the fleet or credential models responsible for content sync.
