# TestFlight rollout plan + metadata baseline

> Companion to [`testflight-readiness.md`](testflight-readiness.md)
> and [`testflight-checklist.md`](testflight-checklist.md). This
> file covers two things: **what we put in App Store Connect**
> (metadata baseline) and **how we widen the beta** (rollout
> sequence).

---

## Metadata baseline

App Store Connect collects this in two places: the **App
Information** block (lives forever) and the **TestFlight** block
(beta-specific). All copy below is a draft — refine before paste.

Current status: internal TestFlight distribution is live for the
`0.5.2` line. Current repo checkpoint is build `13`. Treat this
document as the operating plan for widening the beta, not as a
pre-upload checklist.

### App Information (App Store Connect → App Information)

| Field | Value | Notes |
|-------|-------|-------|
| **Name** | DropStation | Single word, matches `CFBundleDisplayName`. |
| **Subtitle** | Synology Download Station companion | App Store displays under the name. 30 chars max; this is 36 → trim if needed. Alternative: *"Manage your NAS downloads"* (calm-utility framing, no brand mention). |
| **Primary category** | Utilities | Calm tooling, not entertainment. |
| **Secondary category** | Productivity | Optional. |
| **Content rights** | Does not use third-party content | True. |
| **Age rating** | 4+ | No user-generated content, no advertising, no objectionable material. |

### TestFlight description (App Store Connect → TestFlight → Test Information)

Plain text, no markdown. Shown inside the TestFlight app to every
invited tester before they install. Keep it short and honest —
this is the first impression a non-developer tester gets of the
app.

```
DropStation is a private iPhone client for Synology Download Station — a calm replacement for the discontinued DS get app.

This is an early beta. The app talks directly to your own Synology NAS over your home or office Wi-Fi. Nothing is sent to any third-party server. There is no account, no telemetry, no analytics.

What works today:
• Sign in to DSM with username + password (+ 6-digit verification code if you have 2FA on)
• Add downloads via magnet link, URL, or .torrent file
• Pause, resume, stop, delete tasks
• Pick the destination folder on your NAS
• Stay signed in across launches

If something goes wrong, please use Settings → Report a bug. The form gathers basic device info (iOS version, app version, anonymized device model) only if you tick the diagnostics checkbox. No passwords, session tokens, or torrent names are ever included.

Requires iOS 26 and a Synology NAS running DSM 7.
```

### Beta description / "What to test" (per-build)

Lives inside the build's TestFlight notes; shown when the tester
opens the build in TestFlight. Use the template in
[`release-notes-template.md`](release-notes-template.md) for the
per-build wording. The first build is a special case — see *First
build notes* below.

### First build's release notes (suggested copy)

```
First TestFlight build. Please confirm:

• On first launch, iOS asks for Local Network permission — does the wording read clearly? Tap Allow.
• Login with your NAS credentials works. If you have 2FA on, enter the 6-digit code from your authenticator app.
• Adding a download via magnet link works.
• Backgrounding and reopening the app keeps you signed in.

Known limitations:
• iPhone only for this beta (iPad layout not yet reviewed)
• No background refresh — the task list updates only while the app is in the foreground
• Single NAS only — multi-server is on the roadmap

Report bugs via Settings → Report a bug. Feature requests via GitHub.
```

### Current build notes — 0.5.2 build 13

Use this shape for build `13` if the TestFlight "What to Test"
field still needs a concise tester-facing summary:

```
DropStation 0.5.2 (build 13).

What changed:
• Dashboard shows active transfers first, including live download/upload speed.
• Free disk space now appears in the dashboard when the NAS reports it.
• Self-signed NAS certificates can be reviewed and trusted in-app.

What to focus on this build:
• Login to a NAS with a self-signed HTTPS certificate and confirm the trust prompt feels clear.
• Start an active download and confirm the dashboard switches from Recently completed to Active now.
• Open Settings → Report a bug and confirm the mail draft contains useful, non-sensitive diagnostics only if you opt in.

Known issues:
• iPad layout not yet reviewed — iPhone only for this beta.
• No background refresh; task list updates only while the app is open.

Report bugs via Settings → Report a bug.
```

### Keywords draft (App Store, used later)

Not required for TestFlight. Captured here so the App Store
listing isn't a blank page when we get there:

```
synology, download station, nas, downloads, torrent client, dsm
```

100-char limit, comma-separated, no spaces after commas (Apple's
indexing is exact-token).

### Support / privacy URL placeholders

App Store Connect requires both even for internal TestFlight.
Use the GitHub URLs until a proper product site exists:

- **Support URL:** <https://github.com/Wenzlik/DropStation/issues>
- **Privacy Policy URL:** <https://github.com/Wenzlik/DropStation/blob/main/docs/release/privacy.md>

---

## Rollout sequence

Four phases, each gated by a clear acceptance condition. Don't
jump phases — every widening adds debug surface area, and DropStation
has only one maintainer, so triage capacity is the bottleneck.

### Phase 1 — Solo internal (You only)

**Goal:** prove the build pipeline. One human, one device, no
support load.

- Current status: active for build `13`.
- Build uploaded; you receive the TestFlight invite as an internal
  tester.
- Smoke checklist from [`testflight-checklist.md` Phase 5](testflight-checklist.md#phase-5)
  passes on your primary device.

**Exit condition:** smoke checklist 100% green, plus seven days
of daily use without a crash or sign-out regression.

### Phase 2 — Trusted friends (3–5 people)

**Goal:** find the bugs you can't reproduce because your NAS,
network, and DSM version are too uniform.

- Add 3–5 people you can text directly when something breaks as
  internal testers (the cap is 100; you don't need a slot for
  external testing yet).
- Personally walk each one through their first install + login.
  Note where they hesitate — that's UX feedback you won't get
  from a bug report.
- Watch App Store Connect → TestFlight → Crashes daily.

**Exit condition:** at least one tester has been running the
build for 14 days without filing a launch failure or hang. At
least one tester is on a NAS configuration meaningfully different
from yours (different DSM version, different network setup, or
both).

### Phase 3 — Wider closed beta (20–50 people, external testers)

**Goal:** stress-test session persistence and connection
resilience at a scale where edge cases actually surface.

- Switch to external testing: requires Beta App Review (first
  external build per version; usually approved within 24 hours).
- Use App Store Connect's *Public Link* off — you want to control
  who joins, not have a random Reddit thread surface it.
- TestFlight description (above) becomes the user-facing copy;
  refine based on Phase 2 feedback before this phase opens.
- Set up a lightweight intake channel — GitHub Discussions or a
  dedicated email — so feedback doesn't all funnel into bug
  reports.

**Exit condition:** crash-free sessions consistently above 99.5%
in App Store Connect's metrics tab. No P0 bugs open. The
roadmap's 0.6 (App Store readiness) milestones — App Store
metadata, accessibility audit, localization — are at least
drafted, not necessarily shipped.

### Phase 4 — App Store preparation

Out of scope for this release-engineering phase. Tracked in
[`../roadmap/ROADMAP_V2.md`](../roadmap/ROADMAP_V2.md) under 0.6.
Worth noting now so we don't accidentally do it earlier than
necessary:

- App Store screenshots (every screen size Apple still requires).
- Marketing copy + App Store description.
- App Review submission, including a working test NAS Apple's
  reviewers can reach (the awkward bit — without a public test
  server, this needs careful prep).
- Continue to justify the current ATS posture: local HTTP via
  `NSAllowsLocalNetworking`, HTTPS everywhere else, and explicit
  self-signed certificate trust through the URLSession delegate.

---

## Operational notes

A few things that aren't a phase but live somewhere in the
process and shouldn't be re-invented when 0.6 comes around:

- **Build numbering rule.** Bump `CURRENT_PROJECT_VERSION` on
  every archive intended for TestFlight upload, even within the
  same `MARKETING_VERSION`. App Store Connect rejects duplicates.
- **Don't tag every TestFlight build in git.** Reserve git tags
  (`v0.5.2`, `v0.6.0`, …) for releases that you actually
  consider shipped to humans-at-large. TestFlight builds churn;
  tags don't.
- **Crash visibility.** TestFlight's built-in crash collection +
  MetricKit is sufficient for the foreseeable future. Don't add
  Firebase / Sentry / Crashlytics — they're privacy-noisy and we
  don't have the traffic to need them.
- **Tester turnover.** TestFlight builds expire 90 days after
  upload. Plan to ship a fresh build at least every ~60 days to
  keep testers on a non-expired build, even if there's nothing
  to ship feature-wise; bump the build number, archive, upload.
