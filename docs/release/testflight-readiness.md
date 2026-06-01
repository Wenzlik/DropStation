# TestFlight readiness audit — internal beta status

> **Scope:** Move DropStation from "Xcode-installed dev build that
> expires in seven days" to "stable, signed, OTA-updatable internal
> TestFlight install". No App Store submission, no analytics SDKs,
> no redesigns. Release engineering only.

This document is the **diagnosis**. The fix plan lives in
[`testflight-checklist.md`](testflight-checklist.md). The rollout
sequence + metadata baseline lives in
[`testflight-rollout.md`](testflight-rollout.md).

---

## Verdict

**Upload path proven.** DropStation is in internal TestFlight
beta. Current repo checkpoint: `MARKETING_VERSION = 0.5.3`,
`CURRENT_PROJECT_VERSION = 15`. The 0.5.3 build is the first
bilingual (en + cs) release.

The original hard blockers from this audit have either been fixed
in the repo or worked around by the proven App Store Connect
upload flow.
This document is now a status record plus maintenance checklist,
not a pre-upload blocker list.

---

## Resolved blockers

### 1. Local Network permission

`Info.plist` now includes `NSLocalNetworkUsageDescription`, so iOS
can show the Local Network permission prompt before DropStation
connects to a NAS on RFC 1918 / `.local` addresses.

### 2. Export compliance friction

`Info.plist` now includes `ITSAppUsesNonExemptEncryption = false`.
DropStation uses OS-standard HTTPS/TLS and qualifies for the
standard exemption, avoiding the repeated App Store Connect
questionnaire on every upload.

### 3. Version / build identity

`project.yml` now records `MARKETING_VERSION: "0.5.3"` and
`CURRENT_PROJECT_VERSION: "15"`. Keep incrementing
`CURRENT_PROJECT_VERSION` for every TestFlight archive, even when
the marketing version stays the same across builds.

### 4. iPad orientation upload blocker

The `UISupportedInterfaceOrientations~ipad` set is present. This
fixes App Store Connect's ITMS-90474 rejection for universal apps
that omit iPad multitasking orientations.

### 5. Xcode Cloud project bootstrap

`ci_scripts/ci_post_clone.sh` is checked in and executable. Xcode
Cloud can generate `DropStation.xcodeproj` from `project.yml` on a
fresh clone before the Archive action runs.

### 6. App Transport Security / self-signed certificates

ATS is narrowed to `NSAllowsLocalNetworking` for cleartext HTTP to
LAN NAS hosts. Self-signed HTTPS is handled explicitly by
`ServerTrustCoordinator` using trust-on-first-use plus
Keychain-backed fingerprint pinning and a user-facing certificate
trust prompt.

---

## Remaining operational gaps

### Signing config is still local/manual

The first TestFlight upload proves that local Xcode signing and
App Store Connect distribution work. The repo still leaves
`CODE_SIGN_STYLE` / `DEVELOPMENT_TEAM` commented out in
`project.yml`, so regenerated projects require manual signing
selection before archiving.

That is acceptable for the current private beta. Before a more
repeatable release flow, either commit the Apple team id with
automatic signing or document the local Xcode signing step as
intentional.

### CI upload remains manual

`.github/workflows/release.yml` builds an unsigned simulator `.app`
for proof-of-compile and explicitly does not produce an `.ipa`.
Xcode Cloud bootstrap exists, but signed upload automation is not
yet treated as source-controlled release infrastructure.

Not blocking. For the first few betas, Xcode Organizer or Xcode
Cloud uploads are still simpler than wiring App Store Connect API
keys into a custom CI pipeline.

### App icon tinted variant — visual sanity still useful

The tinted-mode (iOS 18+ Home Screen) variant ships as a 1024×1024
PNG generated from `icon-tinted.svg`. The SVG is correct (white
foreground on transparent background) but the resulting PNG hasn't
been visually checked on a real device in tinted Home Screen mode.

**Not blocking.** Worth eyeballing on a device once we install the
first TF build; if the silhouette is unreadable, regenerate from
the SVG with better contrast and re-archive.

---

## Things that are fine

These were audited and are **not** in the way of TestFlight:

- **Debug-only code paths.** `DSLog` (`#if DEBUG`-gated `print`),
  `DownloadTaskStore.makeForTesting` (`#if DEBUG` extension). No
  release-side logging leaks; no debug overlays; no asserts that
  fire in Release.
- **No localhost / dev URLs / hard-coded credentials** anywhere in
  the binary. All server addresses come from the user-typed
  `ServerConfig`.
- **No third-party SDKs.** Nothing to audit for analytics, ads,
  or trackers. Privacy posture is automatically clean.
- **Startup resilience.** `restoreOnLaunch` is idempotent
  (`didRestoreOnLaunch` guard). `SessionStore` covers the four
  launch cases — no saved SID, valid SID, expired SID, NAS
  unreachable — and the offline case auto-recovers via
  `NWPathMonitor`. A first-time beta tester with no saved config
  lands cleanly on the login screen rather than on a blank or
  failed view.
- **Magnet URL scheme registered.** `magnet:` is wired through
  `CFBundleURLTypes`; Safari hand-off works without further
  Info.plist changes.
- **App Transport Security.** Narrowed in 0.5.1: self-signed
  certificates are now handled by the `ServerTrustCoordinator`
  URLSession delegate (trust-on-first-use + pinning), whose
  `.useCredential` overrides ATS's cert-chain requirement — so
  full ATS stays on for HTTPS without a blanket exception. The
  only remaining ATS relaxation is `NSAllowsLocalNetworking`
  (cleartext HTTP to a LAN NAS with HTTPS disabled). Note:
  `NSAllowsArbitraryLoads` never actually *trusted* self-signed
  certs — it relaxes ATS cipher/cleartext rules, but a
  self-signed cert still fails server-trust evaluation until a
  delegate accepts it. The earlier wording here (and in the
  checklist) was wrong; the delegate is what makes self-signed
  work, and the narrowed ATS is much easier to justify at App
  Store review.
- **Permission surfaces.** SwiftUI `.fileImporter` (no
  `NSDocumentPickerUsageDescription` needed), `PasteButton` /
  one-way `UIPasteboard.general.string = …` write (no
  `NSPasteboardUsageDescription` needed), `MFMailComposeViewController`
  (no extra entitlement). Local Network is covered by
  `NSLocalNetworkUsageDescription`.
- **Crash reporting.** Built-in TestFlight crash collection +
  MetricKit on iOS 13+ gives us crash + hang + disk-write reports
  in App Store Connect → TestFlight → Crashes, no SDK needed.

---

## What's deliberately out of scope for this phase

- App Store review-grade copy, screenshots, marketing assets.
- A signed CI/CD pipeline. Manual archive + Transporter is fine
  until release cadence justifies automation.
- A dedicated dark-appearance app icon. The light icon is used in
  Dark Mode today; acceptable for a beta.
- Per-domain ATS exceptions. Done differently than originally
  planned: the beta line narrowed the blanket
  `NSAllowsArbitraryLoads` to `NSAllowsLocalNetworking`
  (cleartext HTTP on the LAN only) + delegate-based self-signed
  HTTPS trust, rather than per-domain exceptions (the NAS host is
  unknown ahead of time, so per-domain was never workable). No
  further ATS work expected before review.
- iPad-specific layout review. The target is universal
  (`TARGETED_DEVICE_FAMILY: "1,2"`), but UI was designed
  iPhone-first. Recommend recording the first TF group as
  iPhone-only until we deliberately review iPad behavior.
