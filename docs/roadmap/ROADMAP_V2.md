# DropStation - Roadmap V2

## Philosophy

DropStation is evolving from:
- a hobby NAS utility
- into a premium native iOS companion app for Synology Download Station.

Priority:
- clarity
- reliability
- speed
- native feel
- calm utility UX

Not:
- feature overload
- analytics dashboards
- automation-heavy complexity

---

# Foundation

## Completed

### Authentication & session
- OTP authentication
- Persistent SID sessions
- Automatic reconnect behavior with `NWPathMonitor` driving the
  Connection lost / auto-reconnect surface
- Session persistence controls (Settings → Privacy → Remember
  session)
- Better offline handling — transient transport-layer failures
  preserve the cached SID, only DSM-confirmed expiry codes
  (105 / 106 / 107 / 119) wipe it

### Visual layer
- Dashboard-first UX (post-login landing screen with focal
  speed / state / metric hierarchy)
- DesignSystem foundation (~20 reusable components: DSCard,
  DSSectionCard, DSHeroCard, DSEyebrow, DSStatusDot, DSStatusBadge,
  DSAvatarCircle, DSQuickAction, DSActivityRow, DSMetricRow,
  DSGroupedRows, DSStatTile, DSProgressSliver, DSRowButtonStyle,
  DSEmptyState, DSErrorState, DSLoadingView + design tokens)
- Downloads redesign (single grouped surface, status dot inline,
  progress sliver, metadata hierarchy)
- Settings redesign (ScrollView + DSSectionCard, account
  identity hero with DSAvatarCircle)
- Modernized login flow (Phase-3 surface treatment, eyebrow
  state headers)
- Polish pass — hero three-way state classifier (no more
  "0 KB/s Working…" frozen-bug look), tiered Downloads metadata,
  light-mode hairline contrast, quieter destructive actions,
  placeholder Quick Actions removed

### Shared infrastructure
- **`DownloadTaskStore`** — single `@MainActor ObservableObject`
  owning the shared `[DownloadTask]` array + 5 s polling timer +
  mutation wrappers (create / pause / stop / resume / delete).
  Dashboard and Downloads tabs read from one source of truth
  instead of running two independent polls.
- Polling lifecycle driven from `RootView.onChange(of: session.state)` —
  starts on `.loggedIn`, stops on every other state. Eliminates
  the cross-tab race the per-view-model timers had.
- 105 forwarding centralised in the store so the recovery card
  receives one signal regardless of which call discovered the
  expired session.

---

# Daily usability

## High priority

### Share Extension

Safari:
```text
Share -> DropStation
```

Goal:
- add torrents/links directly from browser

---

### Notifications

Needed:
- download completed
- failed task
- NAS unreachable

---

### Better task detail

Goal:
- richer metadata
- cleaner hierarchy
- modern detail presentation

---

### Multi-server support

Goal:
- support multiple Synology servers
- quick switching
- future-ready architecture

---

# Distribution

## App Store readiness

- Privacy policy
- App review demo NAS
- TestFlight workflow
- Localization
- Accessibility review
- Screenshots & previews
- App Store copy
- Support URL

---

# Power-user features

## Lower priority

- RSS automation
- advanced search
- widgets
- analytics/charts
- automation systems

Avoid prioritizing these before:
- stability
- usability
- App Store readiness

---

# Explicit non-goals

Avoid:
- reverse-engineering Secure SignIn
- giant custom navigation systems
- overbuilt architecture rewrites
- flashy UI trends
- feature creep before stable daily usability

---

## Product direction

Desired identity:

```text
premium NAS companion
```

Not:

```text
torrent power-user kitchen sink
```
