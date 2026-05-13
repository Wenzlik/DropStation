# Changelog

All notable changes to **Syno Get** are recorded here. The format is loosely
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — Unreleased (in progress)

> Tracking the in-flight 0.3 work. Items move out as features land in
> [ROADMAP.md](ROADMAP.md) → here, and the date stamps when the tag is cut.

### Added
- **Tinted app icon variant** for iOS 18+ tinted Home Screen mode — a
  single-colour silhouette of the download arrow + tray, so the icon
  stays legible under the user's tint instead of degrading.
- **Task type icons** — a small SF Symbol left of the title
  distinguishes BT / HTTP / FTP / NZB / eMule at a glance, both on
  list rows and the detail header.
- **Animated numeric updates** — `.contentTransition(.numericText)` on
  every refreshing speed / size / percentage value. Numbers tick
  smoothly instead of flickering.

### Changed
- **Glass card rows** in the task list — `.listStyle(.plain)` with each
  row wrapped in `.glassEffect(in: .rect(cornerRadius: 18))` on a
  system-background gradient. Rows visibly float as iOS 26 glass
  cards instead of sitting inside a solid list container.
- **Status-tinted progress bars** — `ProgressView` tints match the
  status pill (green downloading/seeding, blue waiting/hash_checking,
  orange paused, red error, grey finished).
- Centralised the status→colour and task-type→symbol mappings on
  `DownloadTask.Status.tintColor` and `DownloadTask.TaskType.systemImage`
  so views stay in sync.

### Removed
- Drop the **keyfun/synology_ds_get** attribution — the networking
  layer has been a full rewrite for several versions; `UPSTREAM-LICENSE-keyfun`
  is gone, README's Credits section is replaced with a one-line
  License pointer, and the LICENSE no longer carries the derivation
  paragraph.

### Added (more)
- **Settings reachable from the login screen** — gear icon in the top
  right opens the same Settings sheet that lives in the task list's
  toolbar. The Account section automatically hides while signed out.
- **In-app changelog viewer** — Settings → About → "What's new" opens
  a Markdown rendering of the bundled `CHANGELOG.md` so it's easy to
  see what each release added without leaving the app.
- New downloads default to the **File** picker (was Link) — the
  common path is picking a `.torrent`; the magnet-URL system handler
  still flips to Link when the app is launched from a `magnet:` URL.

### Fixed
- **Add download by .torrent file** finally works against DSM 7. The
  documented `SYNO.DownloadStation.Task` create endpoint kept
  returning 101 Invalid parameter for multipart uploads regardless of
  spec compliance; switched the file-upload path to the
  `SYNO.DownloadStation2.Task` endpoint at `/webapi/entry.cgi` (what
  DSM's own web UI uses), including the required `type`,
  `destination`, `create_list`, `mtime`, `size`, `file=["torrent"]`,
  and `torrent` fields, with `_sid` carried in the URL query.
- **Add download by magnet/URL** also failed with 101 when the URI
  contained `&` characters (every multi-tracker magnet). The form
  encoder was using `.urlQueryAllowed`, which permits `&` `=` `+`
  inside values — so a magnet's tracker chain was parsed by the
  server as additional form parameters. Switched the encoder to a
  strict RFC 3986 unreserved character set; bumped the URI flow to
  `version=3` (required for the `uri` parameter and `destination`).
- **Network switch no longer pops error alerts.** Wi-Fi ⇄ cellular
  handoffs left URLSession with stale connections; the next 1–2
  auto-refresh ticks failed with `URLError.networkConnectionLost` /
  `.timedOut` / `.cannotConnectToHost` and each one popped an alert.
  Transient errors during the background poll (transport errors plus
  HTTP 5xx) are now swallowed silently; the list keeps its last good
  state and a successful poll clears any stale message.

---

## [0.2.3] — 2026-05-12

### Changed
- **Stop pretending push approval works.** The auth.cgi push behaviour
  could not be made reliable across 0.2.0–0.2.2; the user's NAS
  alternated between sending a push and silently going to TOTP-only,
  with no documented way to detect or control which. Give up on the
  hybrid UI: the 2FA card is back to being a plain OTP entry — type
  the 6-digit code from the Secure SignIn Codes tab (or Google
  Authenticator, 1Password, …) and submit. No more polling, no more
  "I approved" button, no more scenePhase auto-retry.
- The simplification from 0.2.2 (no `enable_device_token`, no
  `device_id` on the login call) is kept — those parameters were the
  cause of the original push regression, and removing them keeps the
  flow minimal.
- Fix: SettingsView no longer references the removed
  `session.hasTrustedDevice` (was breaking the build under 0.2.2).

## [0.2.2] — 2026-05-12

### Fixed
- **Synology Secure SignIn push approval now works.** 0.2.0 stopped
  receiving pushes after a refactor added `enable_device_token=yes` and
  `device_id` to the login call — those parameters switch DSM into a
  TOTP-only flow that suppresses the push notification. The login
  request now sends just account/password (plus an OTP code when the
  user types one), which is what the very first build did and is what
  triggers the push.
- 2FA card again has the "I approved — sign in" button and the
  scenePhase observer that auto-retries the login as soon as the user
  comes back from the Synology Secure SignIn app, so the typical flow
  is: tap Sign in → approve in Secure SignIn → switch back → in.

### Changed
- **Trust-this-device toggle removed.** It was paired with
  `enable_device_token`, which we no longer send. Trade-off accepted
  here: the saved SID still keeps you logged in for the DSM session
  lifetime (typically ~8 h), but a fresh re-login after that triggers
  a push approval rather than skipping it via device token. A push is
  one tap; the previous behaviour silenced the push entirely and was
  unintentionally worse.

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

[0.3.0]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.3.0
[0.2.3]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.2.3
[0.2.2]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.2.2
[0.2.1]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.2.1
[0.2.0]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.2.0
[0.1.0]: https://github.com/Wenzlik/SynoGet/releases/tag/v0.1.0
