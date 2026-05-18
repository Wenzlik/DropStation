# Changelog

All notable changes to **DropStation** are recorded here. The format is loosely
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] — 2026-05-18

### Added
- Sign in via DSM web login in a WKWebView (Synology Secure SignIn push approval works)
- Picker on the sign-in screen to choose verification code vs. Secure SignIn
- "Re-authenticate now" in Settings to trigger a fresh 2FA challenge
- Session cookies persisted in Keychain for cross-launch session restore

### Changed
- Sign-out now wipes SID, cookies, and WKWebsiteDataStore (full cleanup)
- Form sign-in clears DSM trusted-device cookies so 2FA always fires
- Secure SignIn web flow now probes Download Station before declaring
  loggedIn; if DSM rejects API access (error 105), surfaces a recovery
  card with "Continue with verification code" instead of a broken task
  list

## [0.3.1] — 2026-05-14

### Added
- Stop a finished torrent (swipe or detail menu)
- Confirm delete with Keep-partial-files option
- Paste clipboard URL in new-download form
- Search by name
- Sort by name / size / date added / date completed
- Set BT task priority
- Set per-file priority inside BT torrents
- "Ended" label for paused-at-100 % rows

### Changed
- Tap the Version row in Settings to open the changelog

### Fixed
- No error alert on launch when the saved session expired
- Stop is reversible (Resume reappears)
- Detail-view menu hides when there's nothing to do

## [0.3.0] — 2026-05-13

### Added
- iOS 26 glass cards + status-tinted progress bars
- Type icons next to titles (BT / HTTP / FTP / NZB)
- Tinted-mode app icon for iOS 18+ Home Screens
- Settings reachable from the sign-in screen
- What's new screen in Settings (this changelog)
- Smoothly animated speed / size / progress numbers

### Fixed
- Adding a .torrent file works against DSM 7
- Magnet links with multiple trackers
- Wi-Fi ↔ cellular switch no longer pops error alerts

### Changed
- New downloads default to the File picker
- Dropped leftover third-party attribution (full rewrite)

---

## [0.2] — 2026-05-12

- Task detail screen + destination picker + live speeds
- Split filter (Downloading / Seeding / Active)
- Redesigned login screen
- DSM 7 fixes for `.torrent` uploads and magnet links
- TOTP-only 2FA

## [0.1] — 2026-05-12

Initial release.

[0.4.0]: https://github.com/Wenzlik/DropStation/releases/tag/v0.4.0
[0.3.1]: https://github.com/Wenzlik/DropStation/releases/tag/v0.3.1
[0.3.0]: https://github.com/Wenzlik/DropStation/releases/tag/v0.3.0
[0.2]: https://github.com/Wenzlik/DropStation/releases/tag/v0.2.3
[0.1]: https://github.com/Wenzlik/DropStation/releases/tag/v0.1.0
