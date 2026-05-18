# Roadmap

Living planning document for upcoming **DropStation** releases. Items move
into [CHANGELOG.md](CHANGELOG.md) once shipped.

After the auth/session rewrite stabilised in 0.4.0, the roadmap pivots
away from filling out features in a utility-style list and toward a
dashboard-first product with a real design system underneath it. The
shift is **incremental**, not a rewrite — each version adds a layer that
can ship on its own.

---

## 0.4.1 — Stabilization & polish

**Goal:** Shake out the new auth/session system under real use. Small,
boring, defensive work — no UI redesign yet.

### Focus
- Auth UX polish
- Recovery flows
- Loading / error states
- Self-signed certificate handling
- Secure SignIn fallback polish
- Debug logging cleanup
- Edge-case fixes

### Tasks
- [ ] Improve "session expired" recovery copy — distinguish DSM-confirmed
      expiry from transient network failure in the message the user sees.
- [ ] Better loading states during launch-time restore / foreground
      probe (placeholder list rather than a flash of the login screen).
- [ ] Retry handling for transient network failures during restore so
      a flaky Wi-Fi handoff doesn't dump the user back to sign-in.
- [ ] Certificate-warning UX cleanup for NAS with a self-signed cert
      (clear "trust this server" choice instead of a generic URLSession
      error).
- [ ] Reduce noisy auth logs in release builds — gate the DSLog
      session/api categories behind `#if DEBUG` where they aren't
      already.
- [ ] Verify foreground probe behaviour after long inactivity
      (overnight background, days suspended) and add tests covering the
      `probeIfStale` throttle.
- [ ] Additional unit-test coverage for restore / logout / "Remember
      session" off paths.

### Non-goals
- No large UI redesign.
- No architecture rewrite.

---

## 0.5.0 — Dashboard & design system

**Goal:** Transform DropStation from a utility-style task list into a
modern dashboard-first experience. Introduce the design-system layer
that future versions build on.

### Primary focus
- Dashboard screen
- Design-system foundation
- Richer task-detail UX
- Native iOS feel
- Reusable components

### Dashboard

New home screen shown after login. Replaces the bare task list as the
post-login landing.

#### Content
- [ ] Active downloads count
- [ ] Current total download speed
- [ ] Current total upload speed
- [ ] Queue count
- [ ] Failed tasks count
- [ ] Recently completed downloads
- [ ] NAS free disk space
- [ ] Quick actions row:
  - [ ] Add magnet link
  - [ ] Pause all
  - [ ] Resume all
  - [ ] Open search

#### UX goals
- Glanceable information.
- "Control-center" feel.
- Minimal taps to important actions.
- Visually richer than the current list-first layout.

#### Design direction
- Cards.
- Grouped sections.
- Large typography.
- Subtle glass / material usage.
- Smooth transitions.
- Native iOS aesthetics.

### Design-system foundation

Introduce a reusable UI layer so each subsequent screen doesn't reinvent
spacing, type, and colour.

#### Reusable components
- [ ] `DSButton`
- [ ] `DSCard`
- [ ] `DSSection`
- [ ] `DSStatTile`
- [ ] `DSErrorState`
- [ ] `DSEmptyState`
- [ ] `DSLoadingView`

#### Design tokens
- [ ] Spacing scale
- [ ] Typography scale
- [ ] Corner-radius rules
- [ ] Elevation / shadow rules
- [ ] Semantic colours

#### Goals
- Consistent spacing.
- Consistent typography.
- Reusable visual language.
- Easier future redesigns.

### Navigation improvements

Move toward a dashboard-first hierarchy.

```
Dashboard
├── Active
├── Queue
├── Completed
├── Failed
├── Search
└── Settings
```

#### Requirements
- Scalable for future multi-server support.
- Better grouping of task states.
- Easier access to common actions.

### Task-detail redesign

Re-cut the torrent / task detail screen around the actual information
hierarchy.

#### Layout goals
- Progress-first layout.
- Richer metadata presentation.
- Better file-list presentation.
- Grouped actions.
- Clearer ETA / speed information.

#### Additions
- [ ] Progress hero section.
- [ ] Speed indicators.
- [ ] Peer / seeder info.
- [ ] File summary.
- [ ] Grouped action buttons.

### Native iOS UX improvements

#### Add
- [ ] Swipe actions.
- [ ] Better context menus.
- [ ] Haptics.
- [ ] Improved pull-to-refresh.
- [ ] Animated loading states.
- [ ] Smoother transitions.

#### Explicitly avoid
- Overdesigned custom navigation.
- Flashy effects.
- Full custom animation systems.
- Complete SwiftUI rewrite.

### Architecture direction

Do **not** do a full rewrite. Move incrementally toward:

```
Core/
Networking/
Features/
Shared/
Persistence/
DesignSystem/
```

#### Potential future modules
- `AuthCoordinator`
- `SessionManager`
- `DashboardFeature`
- `DownloadTaskStore`
- `BackgroundRefreshService`

---

## 0.6.0 — Sharing & notifications

### Features
- [ ] Share Extension
- [ ] Magnet-link sharing from Safari
- [ ] `.torrent` file import
- [ ] Download-completed notifications
- [ ] Failed-download notifications
- [ ] Background-refresh improvements

---

## 0.7.0 — Multi-server & iPad

### Features
- [ ] Multiple NAS servers
- [ ] Server switcher
- [ ] iPad `NavigationSplitView`
- [ ] Better large-screen layouts

---

## 0.8.0 — Automation & discovery

### Features
- [ ] RSS support
- [ ] Search providers
- [ ] Saved searches
- [ ] Smart filters
- [ ] Auto-download rules

---

## 0.9.0 — TestFlight readiness

### Features
- [ ] Apple Developer integration
- [ ] Signing / notarization cleanup
- [ ] Privacy manifest
- [ ] Telemetry / crash reporting
- [ ] TestFlight internal beta

---

## 1.0.0 — Public release

### Goals
- [ ] Production polish
- [ ] Accessibility pass
- [ ] Onboarding polish
- [ ] App Store assets
- [ ] Screenshots
- [ ] Documentation
- [ ] Stability / performance pass

---

## Important product direction

**Do not** pursue undocumented reverse-engineering of Synology Secure
SignIn internals unless Synology officially exposes API support.

Primary supported auth remains:
- OTP + persistent SID session

Secure SignIn remains:
- Convenience DSM web login.
- Fallback / recovery UX.
