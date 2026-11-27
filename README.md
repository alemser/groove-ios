# Groove for iOS

A native SwiftUI companion for the [Groove](https://github.com/alemser/groove-catalog)
music-recognition stack. Manage your library and catalog from your phone: watch
recognitions land live, browse releases and tracks, fix up metadata, clear
the review queue and control the rig — all against your `groove-catalog` server on the LAN.

<p align="center"><em>Dark, studio-cohesive design · live now-playing · offline-friendly editing</em></p>

## Features

| Tab | What it does | Catalog API |
|-----|--------------|-------------|
| **Home** | Now playing (a mini bar opens the full player), catalog session, remote, stylus, what needs review, recognition pause, and a setup checklist on a new board. | `GET /status`, `POST /identity/album-programme/confirm-session`, `GET /rig/remote/layout`, `GET /catalog/stylus`, `PATCH /identity/recognition/settings` (`suspended`) |
| **Now Playing** (from Home) | Live now-playing with artwork, smooth progress, source/format/confidence badges. Polls while foregrounded. Floats the "which pressing is playing?" question when an album is in the library on more than one release. | `GET /status`, `POST /identity/album-programme/choose-edition`, `…/dismiss-edition-question` |
| **Library** | Release grid with the playing pressing marked, review banners, Needs Review (plays to associate, albums to add, enrich jobs to confirm or discard), drag a track onto an album, all releases, add a release by search or barcode, edit or remove a release. | `GET /catalog/releases`, `GET /catalog/library/suggestions`, `GET /catalog/plays/pending-association`, `GET /catalog/tracks/pending-release`, `GET /catalog/identify/search`, `POST /catalog/user-releases/save`, `…/enrich/jobs`, `…/enrich/releases/{id}/confirm`, `DELETE /catalog/library/releases/{source}/{release_id}` |
| **Track detail** | Artwork, metadata, provider-vs-display names, recent plays, fingerprint count. Edit display title/artist/album + media format, change its release, reset to provider, or delete. | `GET /catalog/tracks/{id}/profile`, `PATCH …/display`, `DELETE …` |
| **Rig** | Stylus tracking and audio input calibration; behind the Rig switch, the amplifier (model, inputs, profiles, whether the selected input may tell vinyl from digital, remote, equipment), the IR bridge, DeviceLink devices and rules. | `GET/PUT /catalog/stylus`, `/rig/capture/{level,gain,input-level}`, `GET/PATCH /rig/control`, `GET/PATCH /rig/amplifier`, `GET/PATCH /rig/amplifier/format-hint`, `/rig/equipment`, `/rig/remote/layout`, `/rig/backends`, `/rig/sessions/learn`, `/rig/devicelink`, `/rig/rules` |
| **Settings** | Recognition providers, metadata enrichers, streaming, stack health, Share Logs for support, updates, switching server, changing the device's Wi-Fi network, device restart and shut down. | `GET /enrich/providers`, `PATCH /enrich/providers/{id}`, `GET /system/logs`, `POST /system/reboot`, `POST /system/poweroff`; on the device, port 80: `GET/PUT /wifi`, `GET /wifi/networks`, `POST /wifi/setup` |
| **Settings → Recognition Providers** | What identifies a spinning record: offline (local-only) mode, chain mode/order/min-confidence, ACRCloud/AudD credentials, up to 3 custom HTTP providers (auth, request, response field mapping, paste-a-sample auto-fill), local-index/provider usage KPIs. | `GET/PATCH /identity/recognition/{providers,settings}`, `PUT …/providers/{id}/credentials`, `PUT …/providers/order`, `POST/PUT/DELETE …/custom-providers(/{slug})`, `GET /identity/observability/providers` |
| **Settings → Streaming** | Turn the AirPlay and Bluetooth receivers on or off (third-party open-source projects; Bluetooth downloads on first use), then pick which ALSA device both play through, out to the amplifier — one wire, one setting. | `GET /rig/streaming/extras`, `POST /rig/streaming/extras/{name}`, `GET/POST /rig/streaming/audio-outputs(/select)` |
| **Settings → Updates** | The board's version, how it installs updates (automatically when nothing is playing, or after asking), Check now, Update now and Cancel. The first connection to a board that has no answer yet asks the same question; an available release (ask first) shows as a notice while the board asks about it (`ask_user`), with Update, Remind me tomorrow and, unless it is a security fix, Don't ask again; swiping it away is Remind me tomorrow, and Cancel puts the release off for a day too. The outcome of an install shows once as a notice. The app gives the board the phone's time zone, which its night install window is read in, whenever the board holds another one. Hidden on a board without the update service. | `GET /system/updates`, `PUT …/preference`, `PUT …/time_zone`, `POST …/check`, `POST/DELETE …/approval`, `POST …/reminder` |

### Which pressing is playing

Asked whenever more than one release in the library matches, unless the track
exists on only one of them. The amplifier's input and the detector's reading of
the medium are **hints**: they mark the likely option and say why, but they do
not answer — the amplifier reports the input it last commanded, and nothing reads
it back, so a selector turned by hand leaves it wrong with no way to know.

The card floats over the screen rather than sitting under the transport: until it
is answered the album shown may be the wrong pressing. "Keep what is showing"
dismisses it without changing anything, so it is never a dead end.

A release cannot be saved or published with a track missing its duration, and
that one is not forceable — the album programme schedules a whole side from
cumulative times.

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
  Features/       Home · NowPlaying · Session · Library · TrackDetail · Review · Rig · Settings · Updates · Health · Onboarding
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
[XcodeGen](https://github.com/yonaskolb/XcodeGen); `Groove.xcodeproj` is not committed, so
generate it after a clone and after any change to `project.yml`:

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
reaches the mock on localhost. Home, Library, Rig and Settings are all populated
with sample tracks and generated cover art.

> Prefer the command line? Build & launch headless:
> ```bash
> xcodebuild -scheme Groove -sdk iphonesimulator \
>   -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
> ```
> Unit tests (`GrooveTests`):
> ```bash
> xcodebuild test -scheme Groove -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
> ```
> On a **physical iPhone**, use your Mac's LAN IP instead of `127.0.0.1` and keep
> the phone on the same Wi-Fi.

## Related repositories

- **[groove-catalog](https://github.com/alemser/groove-catalog)** — library store, enrichment, studio UI, and the API this app consumes
- **[groove-identity](https://github.com/alemser/groove-identity)** — recognition runtime
- **groove-listener / groove-detector** — acoustic hints and the PCM tap
