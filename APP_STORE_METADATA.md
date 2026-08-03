# App Store metadata

This file is the source copy for the English (U.S.) App Store listing for Apple ID `6792223291`.

## Product page

- Name: `PortOS: Private AI Hub`
- Subtitle: `Your private PortOS companion`
- Primary category: Productivity
- Secondary category: Utilities
- Price: Free
- Availability: All 175 App Store countries and regions
- Distribution: Public App Store
- Promotional text: `Connect every PortOS instance on your tailnet, capture ideas by voice or text, and run safe native actions—without a PortDeck-operated cloud.`
- Keywords: `self-hosted,AI,Tailscale,server,fleet,automation,dictation,notes,privacy,homelab`
- Marketing URL: `https://github.com/atomantic/PortOS`
- Support URL: `https://github.com/atomantic/PortDeck/issues`
- Privacy policy URL: `https://github.com/atomantic/PortDeck/blob/main/PRIVACY.md`
- Copyright: `2026 ShadowPuppet, LLC`
- Age rating: 4+ (with Apple's regional equivalents)
- App privacy: Data Not Collected

## Description

PortOS is the native iPhone and iPad companion for your self-hosted PortOS fleet.

CONNECT YOUR FLEET

Add multiple PortOS instances over Tailscale, see connection health at a glance, select the active destination, and inspect federation peers from one native control surface.

CAPTURE FROM ANYWHERE

Send typed notes or on-device dictation to Brain or Daily Log on the PortOS instance you choose. Your phone transcribes speech locally and sends text—not an audio archive.

RUN SAFE QUICK ACTIONS

PortOS publishes a palette-safe action manifest. The app turns those approved actions into native forms, validates required fields, and confirms destructive operations before sending them.

PRIVATE BY DESIGN

There is no PortDeck-operated cloud. Instance credentials stay in Apple Keychain. Optional iCloud Keychain sync can keep fleet profiles and passwords available across your opted-in devices. Your notes, logs, and action content go directly to the PortOS machine you select.

REQUIRES PORTOS

PortOS is self-hosted software for machines you own and manage. This companion app does not provide hosted PortOS service. An offline demo is included so you can explore the experience before connecting your fleet.

## App Review notes

This app has **no user accounts, sign-in, registration, or hosted service**. Please do not request a demo username or password.

The optional “PortOS password” field is not an app login: it is HTTP Basic authentication for a user's own self-hosted PortOS server, and is only shown after that server reports it requires a password.

For complete review without a server or credentials, open **Explore Demo** on the initial Fleet screen, or choose **Settings → Explore offline demo**. This launches a fully featured demo with three fictional PortOS instances. It requires no login, password, account, network access, Keychain, or iCloud access; exit with **Done**. For live use, users add their own PortOS instance reachable over Tailscale.

The app permits HTTP connections because users may operate PortOS on dynamic private Tailscale, MagicDNS, or local-network addresses that cannot be enumerated as static ATS exception domains. HTTPS is supported and uses normal system trust evaluation; the app never disables certificate validation. The offline review demo makes no network requests.
