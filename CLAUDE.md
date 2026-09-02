# CLAUDE.md — groove-ios

No `AGENTS.md` exists in this repo (unlike its 6 backend siblings) — nothing else to import,
this file is the whole thing.

## Project overview

**groove-ios** is the native SwiftUI companion app for the Groove/Oceano stack — manage your
library and catalog from your phone, watch recognitions land live, browse releases and tracks,
fix up metadata, clear the enrichment review queue, control the rig, and (as of 2026-09-02, in
progress) onboard a new headless device over Bluetooth. It talks entirely to a `groove-catalog`
server over HTTP on the LAN; it does not talk to `groove-identity`/`groove-detector`/
`groove-listener` directly, and does not persist a library of its own beyond `AppSettings`'
connection info.

**Consumer-facing brand name is "Oceano"**, not "Groove" — the `groove-*` prefix is an internal
codebase convention only (see `CFBundleDisplayName` in `Info.plist`, `OceanoWordmark`,
`ConnectView`'s copy). Never let an internal repo name leak into UI copy, an advertised BLE
device name, or anything else a user sees — this shipped wrong once already (BLE peripheral
advertised as "Groove-A909" before being caught and fixed).

## Cross-repo context

System-wide architecture, current hardware state (which box is "oceano" right now — it moves),
and engineering principles shared across every `groove-*` repo live in
[groove-system](https://github.com/alemser/groove-system).

## Response language

Respond in **English**. Code, comments, commit messages, and docs are English regardless.

## Hard rules specific to this repo

1. **No iOS Simulator.** Boot + install is too heavy on the dev Mac, and the real target
   (Bonjour/mDNS behavior, CoreBluetooth, LAN connectivity) differs from the simulator anyway.
   Verify with a compile-only build instead:
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
     -project Groove.xcodeproj -scheme Groove \
     -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
   ```
   Nothing is tested live until the operator rebuilds and reinstalls from Xcode themselves —
   there is no CI/OTA path. Say so explicitly rather than claiming something works.
2. **Don't mirror a web Studio UI decision onto iOS sight-unseen.** What reads as decluttering
   on a wide settings page can read as "everything vanished" on a phone screen even when the
   code does exactly what was asked — this has been wrong before and only caught once the
   operator saw it running. Propose the port and ask, or name the concrete on-screen effect
   explicitly, before committing.
3. **New risky/unverified functionality (real Bluetooth pairing, anything touching real device
   credentials) goes on a feature branch, not `main`** — same branch-first + field-test
   discipline as the backend repos, even though this repo has no service to restart. Low-risk
   UI/bugfix work has historically landed directly on `main` here; use judgment, but anything
   that can only be proven by a live device test belongs on a branch until that test happens.

## Architecture notes

- `Core/APIClient.swift` — thin HTTP client; `Error.localizedForDisplay` is the one place error
  text is decided, don't reimplement `(error as? APIError)?.localizedDescription ?? ...` inline.
  GET requests retry once with backoff (mDNS resolution on cold launch is flaky) — see the file's
  `execute(_:)` doc comment before changing retry behavior.
- `Core/Poller.swift` — shared polling-loop primitive; every screen that polls the catalog for
  live state (`NowPlayingModel`, `CatalogSessionModel`, `AttentionCenter`) uses this instead of
  hand-rolling a `Task` loop. Add new pollers here, don't duplicate the loop shape.
- `DesignSystem/Artwork.swift` — the only `AsyncImage` call site in the app; it retries on
  failure (a single blip fetching cover art over the LAN used to leave a permanent placeholder).
- A model with more than one concurrent async fetch (`async let`) must gate its error phase on
  the *primary* fetch only — a secondary fetch failing should degrade to the previous value
  (`(try? await x) ?? previousValue`), not blank the whole screen. This exact bug shipped in
  `ReleasesModel` and 3 other models before being caught and fixed as a batch.
- `Core/BLEProvisioningClient.swift` / `Features/Onboarding/` — CoreBluetooth central for
  headless-device WiFi onboarding (groove-provision's BLE GATT protocol). See groove-provision's
  `PROTOCOL.md` for the wire contract; UUIDs must match exactly on both sides.

## Documentation hygiene

| Change type | Update |
|---|---|
| New settings/connection fields | `AppSettings.swift`, this file if the behavior is non-obvious |
| A screen's error-handling pattern changes | Check it doesn't reintroduce the all-or-nothing `async let` bug above |
| BLE protocol changes | groove-provision's `PROTOCOL.md` (shared contract, both sides must agree) |
