# Groove for iOS

A native SwiftUI companion for the [Groove](https://github.com/alemser/groove-catalog)
music-recognition stack. Manage your library and catalog from your phone: watch
recognitions land live, browse releases and tracks, fix up metadata, and clear
the enrichment review queue — all against your `groove-catalog` server on the LAN.

<p align="center"><em>Dark, studio-cohesive design · live now-playing · offline-friendly editing</em></p>

## Features

| Tab | What it does | Catalog API |
|-----|--------------|-------------|
| **Now Playing** | Live now-playing with artwork, smooth progress, source/format/confidence badges. Polls while foregrounded. | `GET /status` |
| **History** | Paginated recognition feed with artwork, relative timestamps, "show unidentified" filter, swipe-to-delete, tap-through to the track. | `GET /catalog/plays`, `DELETE /catalog/plays/{epoch}` |
| **Library → Releases** | Searchable grid of confirmed editions with owned badges; open a release to see metadata and remove owned editions. | `GET /catalog/releases`, `DELETE /catalog/library/releases/{source}/{release_id}` |
| **Library → Tracks** | Infinite-scroll catalog with confirmed/edited/format badges and on-device filtering. | `GET /catalog/tracks` |
| **Track detail** | Artwork, metadata, provider-vs-display names, recent plays, fingerprint count. Edit display title/artist/album + media format, reset to provider, or delete. | `GET /catalog/tracks/{id}/profile`, `PATCH …/display`, `DELETE …` |
| **Review** | Pending associations (accept suggestion / dismiss) and enrich jobs; open a job to confirm or discard release candidates with tracklists. | `…/plays/pending-association`, `…/associate`, `…/enrich/jobs`, `…/enrich/releases/{id}/confirm` |
| **Settings** | Connect to a server (with live test), toggle metadata enrichers, view stack health. | `GET /status`, `GET /enrich/providers`, `PATCH /enrich/providers/{id}` |

## Design

The visual language mirrors the groove-catalog **studio** web UI so the phone and
browser read as one product — near-black surfaces (`#0B0B0B`), a teal primary
accent (`#4FD1D9`), and warm gold (`#C5A059`) for confirmed / owned states. Built
with modern SwiftUI: `@Observable` models, `NavigationStack` value routing,
`async/await` networking, pull-to-refresh, swipe actions, context menus, haptics,
Dynamic Type, and full dark mode.

## Architecture

```
Groove/
  App/            App entry + root TabView / onboarding gate
  Core/           AppSettings (persisted), APIClient, CatalogService, Formatters
  Models/         Codable models decoded with .convertFromSnakeCase
  DesignSystem/   Theme (brand palette), reusable Components, Artwork
  Features/       NowPlaying · Plays · Library · TrackDetail · Review · Settings · Health
```

`CatalogService` is the single typed facade over every endpoint the app uses, so
the wire contract lives in one place. Views depend on small `@MainActor`
`@Observable` models; there is no third-party dependency.

## Requirements

- iOS 17.0+
- Xcode 16+ (developed against Xcode 26 / iOS 26 SDK)
- A reachable [`groove-catalog`](https://github.com/alemser/groove-catalog) server
  (default port `7073`). The app talks plain HTTP over the LAN, so App Transport
  Security is configured for local networking.

## Build & run

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (committed for convenience):

```bash
brew install xcodegen        # if you don't have it
xcodegen generate            # regenerate Groove.xcodeproj from project.yml
open Groove.xcodeproj         # build & run on a simulator or device
```

On first launch, enter your catalog server's host/IP and port; the app verifies
the connection before saving it. Change it any time in **Settings → Catalog Server**.

## Try it with mock data (no backend)

Preview every screen with realistic sample data — no Pi, no catalog server:

```bash
# 1. Start the bundled fake catalog (pure Python 3, no dependencies).
#    Leave it running in its own terminal; Ctrl-C to stop.
python3 Mock/mock-catalog.py            # serves http://127.0.0.1:7073

# 2. In another terminal, open and run the app on a simulator.
open Groove.xcodeproj                    # press ▶︎ Run (⌘R) on an iPhone simulator
```

In the app's connect screen, enter host **`127.0.0.1`**, port **`7073`**, scheme
**http**, and tap **Connect**. The simulator shares your Mac's network, so it
reaches the mock on localhost. Now Playing, History, Library, and Review are all
populated with sample tracks and generated cover art.

> Prefer the command line? Build & launch headless:
> ```bash
> xcodebuild -scheme Groove -sdk iphonesimulator \
>   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
> ```
> On a **physical iPhone**, use your Mac's LAN IP instead of `127.0.0.1` and keep
> the phone on the same Wi-Fi.

## Related repositories

- **[groove-catalog](https://github.com/alemser/groove-catalog)** — library store, enrichment, studio UI, and the API this app consumes
- **[groove-identity](https://github.com/alemser/groove-identity)** — recognition runtime
- **groove-listener / groove-detector** — acoustic hints and the PCM tap

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
