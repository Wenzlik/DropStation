# DropStation

A modern iPhone client for **Synology Download Station** — the replacement for
the discontinued **DS get** app.

> Current version: **0.4.0** — see [CHANGELOG.md](CHANGELOG.md) for what's
> shipping and [ROADMAP.md](ROADMAP.md) for what's planned.
> Picking up the repo as a contributor (or AI assistant)? Start with
> [AGENTS.md](AGENTS.md).

## What it does

DropStation connects to your Synology NAS and lets you manage Download
Station from your iPhone. Sign in with your DSM credentials — either by
typing a TOTP code into the app or by approving a push notification in
Synology Secure SignIn ([sign-in methods](#sign-in-methods) below) — then:

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

The app stays signed in across launches — the Download Station SID
and Secure SignIn cookies live in the iOS Keychain so a cold start
goes straight to the task list, with no OTP prompt until DSM
actually expires the session. Passwords are **not** persisted. You
can opt out of session persistence in Settings → Privacy via the
**Remember session** toggle (defaults on; flipping it off clears
the saved SID, cookies, and session metadata and forces a fresh
sign-in on every cold start). The app recovers silently from Wi-Fi ↔
cellular switches and runs on iOS 26 or newer.

## Sign-in methods

DropStation supports two paths through DSM's 2-factor authentication:

- **Verification code (TOTP)** — Default. Type your username and
  password into the app; when DSM challenges for a second factor, enter
  the 6-digit code from a TOTP app (Synology Secure SignIn Codes tab,
  Google Authenticator, 1Password, …). Uses
  `SYNO.API.Auth` over `auth.cgi`.
- **Secure SignIn app** — DSM's "Approve sign-in" push notification.
  The app opens the real DSM web login inside a `WKWebView`; you sign
  in there (username + password) and tap Approve on the notification
  that pops up in Synology Secure SignIn. DropStation harvests the
  resulting session cookies and probes Download Station to confirm
  the session is usable. **Best-effort:** Synology binds API
  permissions to the session name passed at login time, and on
  strict DSM configurations the cookie-derived session doesn't
  grant Download Station access (Synology error 105). When that
  happens, the app shows a recovery card pointing you at the
  verification-code path, which always works.

After the first successful sign-in, the session is restored
automatically on every relaunch (SID + cookies kept in the iOS
Keychain). "Sign out" clears the SID, cookies, session metadata,
any legacy password an older build may have left behind, and the
WKWebsiteDataStore — so the next launch starts from a fresh
sign-in screen.

## Installing

DropStation is currently distributed as source — there is no public
TestFlight or App Store listing yet. To run it on your own device:

```bash
git clone https://github.com/Wenzlik/DropStation.git
cd DropStation
brew install xcodegen
xcodegen generate
open DropStation.xcodeproj
```

Then build & run on an iPhone simulator or a physical device from
Xcode. On the first launch the app asks for the NAS scheme / host /
port and credentials.

### GitHub Releases

Tagging `vX.Y.Z` produces a [GitHub Release](https://github.com/Wenzlik/DropStation/releases)
via CI with a zipped `.app` attached. **That zip is a simulator smoke-test artefact, not
an installable iPhone build:** it is unsigned, has no provisioning
profile, and cannot be sideloaded onto a physical device or imported
into TestFlight. Use it to verify the tagged commit compiles or to
drop into the iOS Simulator. Proper distribution lands in a later
release once a TestFlight pipeline is set up (tracked in
[ROADMAP.md](ROADMAP.md)).

## Known limitations

- **No installable iOS build.** As above — TestFlight / App Store
  distribution is on the roadmap, not in 0.4.
- **No background refresh / completion notifications yet.** Refresh
  ticks only while the app is in the foreground.
- **Single NAS only.** Multi-server switching is on the 0.5 roadmap.
- **iOS 26 required.** The app leans heavily on iOS 26 Liquid Glass.
- **Secure SignIn web flow needs a working DSM web UI.** If the user
  has disabled the DSM web login (or it's behind a reverse proxy with
  Path rewriting that doesn't preserve `/webman/`), use the verification
  code method instead.

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
