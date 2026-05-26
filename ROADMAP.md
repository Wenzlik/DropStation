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

Three items from this section shipped as part of 0.5.0 (transient
vs. expiry distinction, ConnectionLost screen, retry handling) —
remaining work below.

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

### TestFlight / submission preparation
- [ ] Apple Developer account setup ($99/year, register
      `com.wenzlik.DropStation`).
- [ ] Proper signing configuration — Xcode-managed certificates +
      distribution profile; remove the CI smoke-test workflow's
      `CODE_SIGNING_ALLOWED=NO` carve-out for archived builds.
- [ ] `PrivacyInfo.xcprivacy` privacy manifest declaring the
      "required reason" API categories the app touches (UserDefaults,
      file timestamps, etc.). Apple rejects uploads without it.
- [ ] Local Network permission review — decide whether `.local`
      mDNS NAS discovery needs `NSLocalNetworkUsageDescription` plus
      a Bonjour service entry, or whether the user-typed host /
      port path keeps us outside the local-network entitlement.
- [ ] Verify whether `NSAllowsLocalNetworking = true` is still
      needed once `NSAllowsArbitraryLoads` is dropped — public hosts
      should go through normal ATS with a valid cert; `.local`
      hostnames need the local-networking carve-out.
- [ ] Crash reporting / diagnostics decision — stay zero-third-party
      (Apple's MetricKit + the built-in crash logs) or accept one
      lightweight SDK. Default leaning: MetricKit only, no
      third-party.
- [ ] Internal beta checklist — up to 100 internal testers by Apple
      ID, no review, install in minutes. External / public TestFlight
      link requires Beta App Review.

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

### App Store readiness
- [ ] **Demo NAS / demo account** strategy for App Review — a
      publicly reachable Synology with a read-only demo account,
      credentials supplied in the App Review notes. Without this
      guideline 5.1.1 makes the review awkward ("requires user
      accounts to function").
- [ ] **Synology trademark disclaimer** — App Store description
      *and* Settings → About both carry: *"Unofficial client for
      Synology Download Station. Not affiliated with or endorsed by
      Synology Inc."* Plan on at least one Resolution Center
      back-and-forth restating it; the reject rate for unofficial
      Synology clients is non-trivial.
- [ ] **Privacy policy** hosted somewhere (GitHub Pages works).
      Short and honest: credentials stay in the iOS Keychain on this
      device, the app talks only to the user-configured NAS, no
      analytics, no third-party SDKs.
- [ ] **App Store privacy nutrition label** — Username + Hostname
      collected for App Functionality, not used for tracking, linked
      to user.
- [ ] **Screenshots and app preview assets** at 6.9″ / 6.7″ iPhone
      (and iPad if supported by then) — script-driven Xcode UI tests
      with localised strings so EN + CS sets stay in sync.
- [ ] **Support URL** (GitHub issues page is the minimum acceptable).
- [ ] **Marketing copy** — App Store description, subtitle, keywords;
      keep it Apple-API-only and trademark-safe.
- [ ] **Accessibility pass** — VoiceOver labels on every icon-only
      button (filter, settings, +, swipe actions), Dynamic Type
      sanity-check across the dashboard and task list. Apple flags
      these.
- [ ] **Final onboarding review** — first-launch host/port/credential
      setup flow walked end-to-end with a fresh install, no shortcuts.

---

## Important product direction

**Do not** pursue undocumented reverse-engineering of Synology Secure
SignIn internals unless Synology officially exposes API support.

Primary supported auth remains:
- OTP + persistent SID session

Secure SignIn remains:
- Convenience DSM web login.
- Fallback / recovery UX.

