# AGENTS.md

A briefing for AI coding assistants (Claude Code, Cursor, Aider, Copilot, …)
and human contributors picking up this repo for the first time.

## The fast read

In order:

1. **[README.md](README.md)** — what the app does and how to build it.
2. **[ROADMAP.md](ROADMAP.md)** — what's planned, broken down by version
   (0.3.1, 0.4, 0.5, 0.6) with implementation notes already filled in.
3. **[CHANGELOG.md](CHANGELOG.md)** — what shipped in each release.
4. **Recent commit messages** — a lot of the "why" lives in commit bodies,
   not just subject lines. `git log --oneline -20` is a good orientation,
   `git log -p -1` on any surprising line shows the reasoning.

If something in the codebase looks odd, check the commit message that
introduced it before changing it — most of the workarounds here exist for
a documented reason.

## Stack

- **iOS 26+**, SwiftUI, Swift 5.9, async/await + actor
- **No third-party dependencies, ever.** Standard library + Foundation +
  SwiftUI + Network + LocalAuthentication only.
- **XcodeGen** for project generation. `DropStation.xcodeproj` is
  gitignored — regenerate from `project.yml` whenever you change source
  layout or build settings.

```bash
brew install xcodegen
xcodegen generate
open DropStation.xcodeproj
```

## Project shape

```
DropStation/                The SwiftUI app
├── Models/                 Codable types, plain structs
├── Networking/             SynologyAPIClient (actor) + response shapes
├── Storage/                Keychain + UserDefaults
├── ViewModels/             SessionStore + per-screen view models
├── Views/                  SwiftUI screens, one file per screen
└── Resources/              Info.plist + Assets.xcassets
DropStationTests/           Unit tests, run via Xcode (⌘U)
project.yml                 XcodeGen specification
icon.svg + icon-tinted.svg  App icon sources (rendered to PNG with rsvg-convert)
```

## Codebase quirks worth knowing

- **File uploads of `.torrent`** go through
  `SYNO.DownloadStation2.Task` at `/webapi/entry.cgi`, not the
  documented DS1 endpoint at `task.cgi`. DS1 silently rejects
  multipart uploads on DSM 7 with `101 Invalid parameter`. The DS2
  payload needs `type`, `destination`, `create_list`, `mtime`, `size`,
  `file=["torrent"]` and the binary as the final part, with `_sid` in
  the URL query.
- **Form-urlencoded values** use a strict RFC 3986 unreserved character
  set (alphanumerics + `-._~`). The default `.urlQueryAllowed` permits
  `&` `=` `+` inside values, which breaks magnet URIs that carry
  multiple trackers — the server parses the trailing `&tr=…` chain as
  new form parameters.
- **Every numeric Synology field** is wrapped in `FlexibleInt64`
  because DSM is inconsistent about returning numbers as JSON numbers
  vs quoted-string numbers vs floats. Same field can come back as
  `5368709120`, `"5368709120"`, or even `5.36e9` across DSM builds.
- **2FA push approval (Synology Secure SignIn) is intentionally not
  supported.** The public `auth.cgi` endpoint can't trigger the push;
  only Synology's first-party apps and the OAuth Service can. Users
  with Secure SignIn enabled read the rotating 6-digit code from the
  app's "Codes" tab and enter it as TOTP. This is documented in
  `SessionStore.State.twoFactorRequired` and on the login API.
- **Launch-time session restore** is driven by `.task` on
  `DropStationApp`'s `WindowGroup`, not from `SessionStore.init()`. The
  `restoreOnLaunch()` entry point is idempotent via a
  `didRestoreOnLaunch` flag.
- **Transient errors** during the background poll (URL errors, HTTP
  5xx) are silently swallowed — see `APIError.isTransient`. The
  list keeps its last good state and the next 5 s tick recovers. Only
  user-initiated actions surface alerts.
- **Status pill / progress tint / type icon** mappings live as
  extensions on `DownloadTask.Status` and `DownloadTask.TaskType`. Add
  new mappings there so views stay in sync.

## Style notes

- **No third-party dependencies.** If a feature really needs one, raise
  it in an issue first; default answer is "find an Apple API".
- Multi-line commit messages with a subject + body that explains
  **why**, not just **what**. The repo's history is a useful
  reference, please don't degrade it.
- Comments where intent matters (especially empty catch blocks for
  transient errors, "magic" Synology fields like `file=["torrent"]`).
- One-word brand name: **DropStation**, no space. Bundle id
  `com.wenzlik.DropStation`.

## Trademark caveat

**Synology** is a registered trademark. Don't:

- Put "Synology" in the app's display name, icon, marketing screenshots
  or App Store name.
- Imitate Synology's brand visuals (colour scheme, iconography).

Do:

- Reference "Synology Download Station" in the App Store description
  with the disclaimer: *"Unofficial client for Synology Download
  Station. Not affiliated with or endorsed by Synology Inc."*
- Mirror that disclaimer in Settings → About once the app reaches
  App Store submission (see ROADMAP 0.6).

## What's not here yet

- **CI** — no GitHub Actions workflow; build verification happens via
  Xcode locally.
- **Localization** — every string is English. Czech localization is on
  the 0.4 roadmap.
- **Accessibility audit** — VoiceOver labels and Dynamic Type
  sanity-checking are listed as 0.6 (App Store) gating work.

## How to make a change

1. Decide which version it fits — open `ROADMAP.md` and find the item.
   If it's not there, add it with a one-line rationale before coding.
2. Implement. If you touched `project.yml`, regenerate the Xcode
   project (`xcodegen generate`).
3. Run tests in Xcode (⌘U). Add coverage for any new model or API
   path.
4. Move the item from `ROADMAP.md` into the `[Unreleased]` (or
   in-flight version) entry in `CHANGELOG.md`. Keep the public-facing
   wording short and concrete.
5. Commit with a multi-line message — subject line under ~70 chars,
   body that explains the why and references API quirks if relevant.
6. Push to `main` (this is a personal project; no PR workflow).
