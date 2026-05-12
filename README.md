# Syno Get

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
- [x] Two-step verification (OTP) with persistent device token
- [x] Session persists across app launches (SID + device_id in Keychain)
- [x] Credentials stored in **Keychain** (not UserDefaults)
- [x] List downloads with progress, size, status
- [x] Add a download from a magnet/HTTP/FTP URI
- [x] Add a download by uploading a local `.torrent` file from the Files app
- [x] Choose download destination by browsing NAS shared folders (FileStation API)
- [x] Pause / resume tasks (swipe from the left)
- [x] Filter list by status (All / Active / Paused / Finished / Error)
- [x] Settings sheet (theme override, account management, app info)
- [x] Delete a download
- [x] Pull-to-refresh + 5s auto-refresh
- [x] `magnet:` URL scheme handler (open magnet links in this app)
- [ ] BT search
- [ ] iPad layout polish
- [ ] Share Sheet extension for adding torrents from Safari

## Tech

- SwiftUI, iOS 26+ (Liquid Glass design language)
- Swift 5.9, async/await, Codable
- No third-party dependencies
- `actor`-based API client
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Building

```bash
brew install xcodegen
xcodegen generate
open SynoGet.xcodeproj
```

Then build & run on an iPhone simulator or a physical device. The first run
asks for the NAS scheme/host/port and credentials.

## Repository layout

```
SynoGet/                    New SwiftUI app (this is what we build)
├── Models/                 Codable types: ServerConfig, DownloadTask, TaskFilter
├── Networking/             SynologyAPIClient (async/await actor)
├── Storage/                Keychain + UserDefaults persistence
├── ViewModels/             SessionStore, TaskListViewModel
├── Views/                  SwiftUI screens
└── Resources/              Info.plist + Assets.xcassets (AppIcon)
SynoGetTests/               Unit tests
legacy-reference/           Original keyfun/synology_ds_get source (UIKit, 2019)
                            Kept for reference while porting / verifying API behavior.
Synology_Download_Station_Web_API.pdf
                            Official Synology DSM Download Station API spec
project.yml                 XcodeGen project specification
icon.svg                    Source for the app icon (rendered to PNG via rsvg-convert)
```

## Synology API

Endpoints used (see `Synology_Download_Station_Web_API.pdf` for the full
spec):

- `SYNO.API.Auth` — login/logout (`/webapi/auth.cgi`)
- `SYNO.DownloadStation.Task` — list/create/delete/pause/resume
  (`/webapi/DownloadStation/task.cgi`)

Authentication uses **API version 6**, which supports `enable_device_token` —
on the first 2FA login the server returns a `did` (device id) that subsequent
logins use in place of the OTP code. Both the SID and the device id are kept
in the Keychain so the user does not have to re-authenticate after every
app launch.

All requests are sent as `application/x-www-form-urlencoded` POST so that
credentials and SIDs do not end up in URL logs (file uploads use multipart,
with the file part last per the Synology spec).

## Credits

The original UIKit codebase that inspired this project is preserved verbatim
under `legacy-reference/`. It is the work of **keyfun**
([github.com/keyfun/synology_ds_get](https://github.com/keyfun/synology_ds_get))
and is MIT-licensed — see `UPSTREAM-LICENSE-keyfun`.

This project is also released under the MIT license; see `LICENSE`.
