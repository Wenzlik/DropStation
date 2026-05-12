# Synology Torrent

A modern iPhone client for **Synology Download Station** — the replacement for
the discontinued **DS get** app.

> Status: **early scaffolding**. The API client compiles and the UI flows are
> wired up, but nothing has been tested against a real DSM yet.

## Why

Synology removed *DS get* from the App Store. There is no first-party way to
control Download Station from an iPhone anymore. This project rebuilds the
missing piece as a small, modern, self-buildable SwiftUI app.

## Features (initial scope)

- [x] Login (username + password, scheme/host/port)
- [x] Two-step verification (OTP)
- [x] Credentials stored in **Keychain** (not UserDefaults)
- [x] List downloads with progress, size, status
- [x] Add a download from a magnet/HTTP/FTP URI
- [x] Delete a download
- [x] Pull-to-refresh + 5s auto-refresh
- [x] `magnet:` URL scheme handler (open magnet links in this app)
- [ ] Pause / resume tasks
- [ ] BT search
- [ ] iPad layout polish
- [ ] Share Sheet extension for adding torrents from Safari

## Tech

- SwiftUI, iOS 17+
- Swift 5.9, async/await, Codable
- No third-party dependencies
- `actor`-based API client
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Building

```bash
brew install xcodegen
xcodegen generate
open SynologyTorrent.xcodeproj
```

Then build & run on an iPhone simulator or a physical device. The first run
asks for the NAS scheme/host/port and credentials.

## Repository layout

```
SynologyTorrent/            New SwiftUI app (this is what we build)
├── Models/                 Codable types: ServerConfig, DownloadTask
├── Networking/             SynologyAPIClient (async/await actor)
├── Storage/                Keychain + UserDefaults persistence
├── ViewModels/             SessionStore, TaskListViewModel
├── Views/                  SwiftUI screens
└── Resources/Info.plist
SynologyTorrentTests/       Unit tests
legacy-reference/           Original keyfun/synology_ds_get source (UIKit, 2019)
                            Kept for reference while porting / verifying API behavior.
Synology_Download_Station_Web_API.pdf
                            Official Synology DSM Download Station API spec
project.yml                 XcodeGen project specification
```

## Synology API

Endpoints used (see `Synology_Download_Station_Web_API.pdf` for the full
spec):

- `SYNO.API.Auth` — login/logout (`/webapi/auth.cgi`)
- `SYNO.DownloadStation.Task` — list/create/delete
  (`/webapi/DownloadStation/task.cgi`)

All requests are sent as `application/x-www-form-urlencoded` POST so that
credentials and SIDs do not end up in URL logs.

## Credits

The original UIKit codebase that inspired this project is preserved verbatim
under `legacy-reference/`. It is the work of **keyfun**
([github.com/keyfun/synology_ds_get](https://github.com/keyfun/synology_ds_get))
and is MIT-licensed — see `UPSTREAM-LICENSE-keyfun`.

This project is also released under the MIT license; see `LICENSE`.
