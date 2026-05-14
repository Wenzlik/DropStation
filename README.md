# DropStation

A modern iPhone client for **Synology Download Station** — the replacement for
the discontinued **DS get** app.

> Current version: **0.3.1** — see [CHANGELOG.md](CHANGELOG.md) for what's
> shipping and [ROADMAP.md](ROADMAP.md) for what's planned.
> Picking up the repo as a contributor (or AI assistant)? Start with
> [AGENTS.md](AGENTS.md).

## What it does

DropStation connects to your Synology NAS and lets you manage Download
Station from your iPhone. Sign in with your DSM credentials (2FA via
TOTP supported), then:

- See every download in one list — progress, speed, size, status — with
  iOS 26 Liquid Glass cards and live, smoothly-ticking counters.
- Tap a task to drill into peers / seeders / leechers, file list,
  tracker URLs, ratio, and ETA.
- Add a new download by pasting a magnet/URL or picking a `.torrent`
  from the Files app. The destination folder is a tap away — browse
  your NAS shared folders directly.
- Pause, resume, or delete with a swipe. Filter the list by
  Downloading / Seeding / Paused / Finished / Error.
- Open magnet links from Safari straight into the app.

The app stays signed in across launches (SID and password held in the
iOS Keychain), recovers silently from Wi-Fi ↔ cellular switches, and
runs on iOS 26 or newer.

## Building

```bash
brew install xcodegen
xcodegen generate
open DropStation.xcodeproj
```

Then build & run on an iPhone simulator or a physical device. On the
first launch the app asks for the NAS scheme / host / port and
credentials.

## Stack

- SwiftUI, iOS 26+ (Liquid Glass design language)
- Swift 5.9, async/await, Codable
- No third-party dependencies
- `actor`-based API client
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Repository layout

```
DropStation/                The SwiftUI app
├── Models/                 Codable types
├── Networking/             SynologyAPIClient (async/await actor)
├── Storage/                Keychain + UserDefaults persistence
├── ViewModels/             SessionStore + per-screen view models
├── Views/                  SwiftUI screens
└── Resources/              Info.plist + Assets.xcassets (AppIcon)
DropStationTests/           Unit tests
project.yml                 XcodeGen project specification
icon.svg                    Source for the app icon
icon-tinted.svg             Tinted-mode variant (iOS 18+ Home Screen)
```

## Synology API

See the official [Download Station Web API guide](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/DownloadStation/All/enu/Synology_Download_Station_Web_API.pdf)
and [DSM Login Web API guide](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Os/DSM/All/enu/DSM_Login_Web_API_Guide_enu.pdf)
for the wire format. Endpoints used:

- `SYNO.API.Auth` — sign-in / sign-out (`auth.cgi`)
- `SYNO.DownloadStation.Task` — list, getinfo, delete, pause, resume,
  and the URI-mode create (`task.cgi`)
- `SYNO.DownloadStation2.Task` — file-upload create at `entry.cgi`
  (DSM 7's newer endpoint; the legacy one silently rejects `.torrent`
  multipart uploads)
- `SYNO.FileStation.List` — list_share / list for the destination picker

Form-urlencoded POST bodies are strictly encoded per RFC 3986 so that
magnet URIs with `&`-separated trackers survive the trip. File uploads
use multipart with the binary as the final part, per Synology's spec.

## License

MIT — see [LICENSE](LICENSE).
