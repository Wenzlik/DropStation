# Changelog

All notable changes to **Syno Get** are recorded here. The format is loosely
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] — 2026-05-12

### Changed
- **2FA flow simplified to TOTP-only.** The 0.2.0 build advertised
  "Synology Secure SignIn push approval" but the public `auth.cgi`
  endpoint we use does not trigger the push — that flow is only
  reachable through Synology's first-party apps or the
  [OAuth Service](https://www.synology.com/en-global/dsm/7.3/software_spec/oauth)
  (separate registration in DSM). The 2FA challenge now just asks for
  a 6-digit code from any authenticator app, including the **Codes**
  tab inside Synology Secure SignIn — which works the same as
  Google Authenticator, 1Password, etc. The polling task,
  Resend-push button, and scenePhase wake-up are all gone with it.

## [0.2.0] — 2026-05-12

### Added
- **Task detail screen** — tap any row in the list to open a drill-down view
  showing peers, seeders, leechers, total peers, per-file progress (BT),
  tracker URLs and status, computed ETA, and ratio. Auto-refreshes every 3 s.
- **Choose download destination** — when adding a new download you can now
  browse the NAS shared folders via the FileStation API and pick a target
  folder; "Default destination" keeps the DSM-configured behaviour.
- **Live speed counters** — each actively-transferring row shows an inline
  ↓ speed; the navigation bar's subtitle shows the aggregate ↓/↑ totals
  across all tasks. No extra API traffic — pulled from the existing list
  refresh.
- **Split filter** — separate **Downloading** and **Seeding** filters, plus
  **All active** as the umbrella category. Easier to spot what's still
  pulling bytes vs. what's just sharing.
- **Synology Secure SignIn push approval** — login no longer asks for an
  OTP code up front. After the first attempt, if the server demands 2FA
  the screen switches to a challenge that polls every 5 s for a push
  approval from your authenticator app; you can also type a 6-digit code
  as a fallback.

### Changed
- **Login screen** redesigned to feel like the Synology DSM sign-in: gradient
  background, centered glass card, single column of fields with icons,
  collapsible server-config disclosure, full-width tinted Sign in button.
- **Active filter** now also includes `.finishing` (still in progress);
  **Finished** is now strictly the `.finished` state.
- Decoding errors now include the JSON key path (e.g. `wrong type — expected
  string at data.tasks[0].additional.detail.create_time`) so future API
  surprises surface immediately instead of as a generic message.
- Repository cleanup — removed the bundled API reference PDF and the
  `legacy-reference/` directory; README links to Synology's hosted copies.

### Fixed
- **Tap on a task crashes with "Decoding error"** — fully rewritten to be
  defensive against Synology's API surface:
  - Every numeric field (`size`, `size_downloaded`, `speed_*`,
    `create_time`, `connected_seeders`, `total_peers`, tracker `seeds` /
    `peers`, etc.) now decodes from JSON number, quoted numeric string, or
    JSON float. DSM versions disagree with the spec and with each other.
  - `getinfo` returns `data: { tasks }` without `total` / `offset` —
    `TaskListData` now treats those as optional.
  - BT torrents can include DHT pseudo-trackers without URLs, padding
    files without filenames, and deselected files without download
    counters; these no longer fail the whole response and are filtered
    out in the detail view.

## [0.1.0] — 2026-05-12

Initial private release. A SwiftUI replacement for the discontinued **DS get**
iOS app, targeting iOS 26 with the Liquid Glass design language.

### Added
- SwiftUI app skeleton with login, task list, add-by-URI / add-by-`.torrent`
  file, pause / resume / delete, pull-to-refresh + 5 s auto-refresh.
- Magnet (`magnet:`) URL scheme handler — magnet links from Safari or other
  apps open Syno Get with the URI pre-filled.
- Async/await `actor`-based `SynologyAPIClient`, modernised from the
  [keyfun/synology_ds_get](https://github.com/keyfun/synology_ds_get)
  reference (UIKit, 2019).
- Keychain-backed session persistence: SID and Synology Secure SignIn
  `device_id` survive app launches so a hot launch goes straight to the
  task list with no prompts.
- Filter list by status (All / Active / Paused / Finished / Error).
- Settings sheet: theme (System / Light / Dark), account management
  (Sign out, Forget this device), about (version, GitHub link,
  attribution).
- App icon (orange gradient + white download-into-tray arrow), generated
  from `icon.svg`.

[0.2.1]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.2.1
[0.2.0]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.2.0
[0.1.0]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.1.0
