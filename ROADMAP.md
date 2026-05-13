# Roadmap

Living planning document for upcoming **Syno Get** releases. Items move
into [CHANGELOG.md](CHANGELOG.md) once shipped.

## 0.3.1 — Quality of life follow-ups

Pass 4 / 5 of the 0.3 cycle. Not shipped in 0.3.0 to keep that release
tight; the work is short and self-contained.

- [ ] **Stop action for active downloads.** Pause is reversible; users want a
      "final" termination they can issue from the row. Synology only exposes
      `pause` and `delete`, so this is really about better delete UX: swipe-delete
      pops a confirmation that also offers "Keep partial files" (maps to
      `force_complete=true`) vs "Delete files" (`force_complete=false`).
- [ ] **Confirm-before-delete** dialog on the swipe-delete action (subsumed by
      the Stop dialog above).
- [ ] **Clipboard hint** in AddTaskView: when `UIPasteboard` contains a
      magnet/HTTP URL, show a "Paste from clipboard" button above the URI
      field.
- [ ] **Search by name** — search field above the task list, incremental
      filter on `task.title`.
- [ ] **Priority change** — tappable priority row on the task detail (DS2
      `SYNO.DownloadStation2.Task.BT` `method=set`) and per-file priority
      picker for BT torrents (DS2 `…Task.BT.File` `method=set`), with
      skip/low/normal/high.

---

## 0.4 — Detail screen, bulk actions, locale

### Detail screen polish
- [ ] Header card with gradient background coloured by status, large title,
      status pill, progress — turns the detail view from a list-of-rows
      into a landing.
- [ ] **Speed sparkline** — store the last ~30 transfer-speed samples and
      render as a tiny `Chart` line in the Transfer section.

### Tactile + visual polish
- [ ] **Haptic feedback** on swipe actions (light) and on destructive
      confirms (success/error).
- [ ] **Empty-state illustrations** with personality — better copy plus
      either a tweaked SF Symbol arrangement or a small custom rendered
      asset.
- [ ] **Stats card at the top of the task list** — `X active · ↓ total ·
      ↑ total · finished today`, replaces or complements the navigation
      subtitle aggregate.

### Power-user features
- [ ] **Bulk select / Edit mode** — multi-select rows, then pause / resume
      / delete all together. Useful for "delete all finished".
- [ ] **Per-task speed limit** — `max_download_rate` / `max_upload_rate`
      via DS2 `Task.BT` edit. Exposed as a Detail → "Speed limit…" row
      with a small number-pad sheet.

### Localization
- [ ] **Czech localization** — `Localizable.strings` for key user-facing
      strings (LoginView, TaskListView, status pill, Settings, AddTask).

---

## 0.5 — Extensions, background, multi-device

### Extensions & background
- [ ] **Share Extension** for `.torrent` files from Safari / Files /
      anywhere. Requires a separate target with an App Group so it can
      reach the same Keychain.
- [ ] **Background refresh** with `BGAppRefreshTask` — poll the task list
      while the app is suspended so we can detect completions.
- [ ] **Completion notifications** — `UNUserNotification` fires when a
      previously-active task transitions to `.finished` (driven by the
      foreground refresh as well as the background task).

### Widgets
- [ ] **Home Screen widget** — small variant showing active task count and
      total ↓ speed; medium variant adds the top 1-2 task progress bars.
- [ ] **Lock Screen widget** (inline / circular) — just the active count
      and ↓ speed.

### iPad / form factors
- [ ] **iPad layout** — `NavigationSplitView` with the task list in the
      sidebar and the detail in the trailing column. Better use of the
      bigger screen than a stretched phone layout.

### Multi-server
- [ ] **Multiple servers** — switch between NASes; per-server Keychain
      slots (already mostly account+host keyed). UI: a "Servers" row in
      Settings + a sidebar quick-switcher.
- [ ] **RSS feeds** — `SYNO.DownloadStation.RSS.Feed` integration with
      auto-add rules; subscribe to a feed, filter by title pattern, and
      let the NAS pull matching torrents automatically.
