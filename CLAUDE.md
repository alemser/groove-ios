# CLAUDE.md — groove-ios

No `AGENTS.md` exists in this repo (unlike its 6 backend siblings) — nothing else to import,
this file is the whole thing.

## Project overview

**groove-ios** is the native SwiftUI companion app for the Groove/Oceano stack — manage your
library and catalog from your phone, watch recognitions land live, browse releases and tracks,
fix up metadata, clear the enrichment review queue, control the rig, and set up a new headless
device's Wi-Fi through the device's own setup network. It talks entirely to a `groove-catalog`
server over HTTP on the LAN; it does not talk to `groove-identity`/`groove-detector`/
`groove-listener` directly, and does not persist a library of its own beyond `AppSettings`'
connection info.

**Consumer-facing brand name is "Oceano"**, not "Groove" — the `groove-*` prefix is an internal
codebase convention only (see `CFBundleDisplayName` in `Info.plist`, `OceanoWordmark`,
`ConnectView`'s copy). Never let an internal repo name leak into UI copy, a network name, or
anything else a user sees — this shipped wrong once already (a device advertised as
"Groove-A909" before being caught and fixed).

## iOS and Android stay in step (hard rule)

**Every change to groove-ios or [groove-android](../groove-android) lands in both apps, in the same
piece of work.** A feature, a fix, a copy change, a new endpoint: port it before reporting it done.
When one platform truly can't do something, say so explicitly instead of letting the apps drift.
groove-android's `CLAUDE.md` maps the two codebases file to file.

## Cross-repo context

System-wide architecture, current hardware state (which box is "oceano" right now — it moves),
and engineering principles shared across every `groove-*` repo live in
[groove-system](https://github.com/alemser/groove-system).

## Response language

Respond in **Portuguese (pt-BR)**. Code, comments, commit messages, and docs stay in English.

## Hard rules specific to this repo

1. **Simulator is fine; real-device behavior still needs the operator.** Build and run in
   the iOS Simulator freely. It shares the Mac's network, so it reaches the catalog on
   oceano; preset the server to skip the Connect screen:
   ```bash
   xcrun simctl spawn booted defaults write com.alemser.groove catalog.host 192.168.178.105
   ```
   Bonjour discovery, Wi-Fi setup against a real board and the camera still need a real device, and
   nothing reaches the phone until the operator rebuilds and reinstalls from Xcode themselves —
   there is no CI/OTA path. Say which of the two you verified rather than claiming it works.
2. **Don't mirror a web Studio UI decision onto iOS sight-unseen.** What reads as decluttering
   on a wide settings page can read as "everything vanished" on a phone screen even when the
   code does exactly what was asked — this has been wrong before and only caught once the
   operator saw it running. Propose the port and ask, or name the concrete on-screen effect
   explicitly, before committing.
3. **New risky/unverified functionality (Wi-Fi setup against a real board, anything touching real
   device credentials) goes on a feature branch, not `main`** — same branch-first + field-test
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
- `DesignSystem/Artwork.swift` — the one place cover art is fetched (its own URLSession loader,
  not `AsyncImage`, because it needs the decoded image's size); it retries on failure (a single
  blip fetching cover art over the LAN used to leave a permanent placeholder). A cover more than
  10% off square (cassette J-card) is drawn whole inside the caller's square slot, never growing
  it — same rule as groove-display and the catalog Studio.
- A model with more than one concurrent async fetch (`async let`) must gate its error phase on
  the *primary* fetch only — a secondary fetch failing should degrade to the previous value
  (`(try? await x) ?? previousValue`), not blank the whole screen. This exact bug shipped in
  `ReleasesModel` and 3 other models before being caught and fixed as a batch.
- `Core/WifiSetupClient.swift` / `Features/Onboarding/` — the board's Wi-Fi setup routes
  (groove-provision's `PROTOCOL.md`); the setup network's prefix and address must match
  it exactly. iOS joins a network from an app only with the Hotspot Configuration capability, which
  this app doesn't have, so the person joins the setup network in Settings → Wi-Fi; groove-android
  joins it from the app. The password is the board's own, on its label: the app never holds one.

## Code quality (mandatory)

Every change follows the code quality rules in groove-system's
[`docs/code-quality.md`](https://github.com/alemser/groove-system/blob/main/docs/code-quality.md)
(local checkout: `../groove-system/docs/code-quality.md`). Read them before
writing code. Before reporting work as done, review the whole diff against
each rule, and fix every deviation or name it in the report.

@../groove-system/docs/code-quality.md

## Documentation hygiene

| Change type | Update |
|---|---|
| New settings/connection fields | `AppSettings.swift`, this file if the behavior is non-obvious |
| A screen's error-handling pattern changes | Check it doesn't reintroduce the all-or-nothing `async let` bug above |
| Wi-Fi setup protocol changes | groove-provision's `PROTOCOL.md` (shared contract, both sides must agree) |
