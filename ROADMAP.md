# Roadmap

Living planning document for upcoming **DropStation** releases. Items move
into [CHANGELOG.md](CHANGELOG.md) once shipped.

## 0.3.1 — Quality of life follow-ups

Pass 4 / 5 of the 0.3 cycle. Not shipped in 0.3.0 to keep that release
tight; the work is short and self-contained.

- [ ] **Stop action.** Real API call, found in dvcol/synology-download:
      `SYNO.DownloadStation2.Task.Complete` `method=start` (id = task ID list).
      Transitions an active / seeding task to the documented `finished` status
      — what DSM web's "End" button does. Add a Stop swipe action (stop.fill
      icon) and Stop entry in the detail-view menu. No new client-side status
      needed; rely on the existing `finished` rendering, just gated so that
      Stop only shows for `canPause` rows.
- [ ] **Confirm-before-delete** dialog with a "Keep partial files" toggle
      (maps to `force_complete=true` vs `false` on the delete call).
- [ ] **Clipboard hint** in AddTaskView: when `UIPasteboard` contains a
      magnet/HTTP URL, show a "Paste from clipboard" button above the URI
      field.
- [ ] **Search by name** — search field above the task list, incremental
      filter on `task.title`.
- [ ] **Sort order for the task list.** Options: name (alphabetical), size,
      date added, date completed — each asc / desc. UI is a sort menu next
      to the filter menu in the toolbar; the selected order is persisted via
      `@AppStorage` so it survives launches. Implementation notes:
      - Sort is client-side. Synology's list endpoint doesn't accept a
        `sort_by` parameter for tasks, so we order `filteredTasks` ourselves.
      - "Date added" uses `additional.detail.create_time` (already decoded);
        "Date completed" needs `completed_time` added to
        `DownloadTask.Additional.Detail` (it's in the API but not in our
        model yet).
      - The list refresh currently asks for `additional=transfer`; bump to
        `additional=transfer,detail` so both timestamps are populated on
        every poll.
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
- [ ] **BT search via Synology's integrated engines** —
      `SYNO.DownloadStation.BTSearch` (`start` → `list` → `clean`). The
      search modules (and any tracker credentials they need) live on the
      NAS, configured in DSM Control Panel → BT Search, so the app
      never touches credentials directly and works for any module the
      user has installed (public engines plus user-installed private
      tracker modules). UI: a search tab with a query field, sort and
      category filters, and a tap-to-add flow that hands the result
      torrent into the existing `createTask` path.

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
      let the NAS pull matching torrents automatically. Particularly
      useful for private trackers that expose a personalised RSS feed
      (passkey baked into the URL): the credential stays in the feed
      URL on the NAS, the app just edits filter rules.

### TestFlight distribution

Low-gate distribution: internal testers only, no formal review.
Targeting this version for the actual roll-out so it lands together
with the share extension / background refresh polish.

- [ ] Enroll in **Apple Developer Program** ($99/year).
- [ ] Register the `com.wenzlik.DropStation` bundle ID in the developer
      portal; let Xcode auto-manage signing certificates and the App
      Store distribution profile.
- [ ] Add `ITSAppUsesNonExemptEncryption = false` to `Info.plist` (HTTPS
      via URLSession is covered by Apple's umbrella, so no export
      compliance paperwork — but the flag must be set explicitly on
      every upload).
- [ ] Add a **`PrivacyInfo.xcprivacy`** privacy manifest declaring the
      "required reason" API categories the app touches (UserDefaults,
      file timestamps). Apple has been rejecting uploads without it
      since late 2024.
- [ ] Archive in Xcode → upload to App Store Connect.
- [ ] Create the App Store Connect listing (the minimal version is
      fine for internal TestFlight — no screenshots / description /
      privacy policy strictly required).
- [ ] Add up to 100 **internal testers** by Apple ID. No review,
      installs in minutes.
- [ ] For external testers / a public TestFlight link, submit for
      **Beta App Review** (lighter than full App Store review,
      typically 24–48 h).

---

## 0.6 — App Store submission

The full gate. Most items are paperwork rather than code; the
trademark disclaimer and the demo NAS are the two things to plan for
carefully.

- [ ] **Privacy policy URL** hosted somewhere (GitHub Pages works).
      Short and honest: "DropStation stores credentials in the iOS
      Keychain on this device only. It connects to the Synology NAS
      you configure and to no other server. No analytics, no
      third-party SDKs."
- [ ] **App Store Connect listing** — category (Utilities), screenshots
      at 6.9″ / 6.7″ iPhone (+ iPad if supported), description with
      the mandatory **trademark disclaimer**: "Unofficial client for
      Synology Download Station. Not affiliated with or endorsed by
      Synology Inc."
- [ ] **In-app disclaimer** in Settings → About: mirror the same line
      so reviewers can see it without leaving the binary.
- [ ] **Privacy nutrition label** filled in App Store Connect (Username
      and Hostname collected for App Functionality; not used for
      tracking; linked to user).
- [ ] **App Transport Security** tightened — drop
      `NSAllowsArbitraryLoads`, add `NSAllowsLocalNetworking = true`
      instead so `.local` NAS hostnames work without HTTPS while public
      hosts go through the normal ATS path with a valid cert.
- [ ] **Demo NAS** for review: a publicly reachable Synology with a
      read-only demo account, credentials supplied in the App Review
      notes. Without this Apple guideline 5.1.1 makes the review
      awkward ("the app requires user accounts to function");
      reviewers want a working sign-in path.
- [ ] **Trademark risk note:** the reject rate for unofficial Synology
      clients is non-trivial. Plan on at least one Resolution Center
      back-and-forth re-stating the disclaimer and that this is a
      third-party client.
- [ ] **Accessibility pass** — VoiceOver labels on icon-only buttons
      (filter, settings, +), Dynamic Type sanity-check on the task
      list. Apple flags these.
- [ ] **App Store screenshots** generated from the simulator on a
      decorated background — a couple of script-driven Xcode UI tests
      with localised strings would future-proof this.
