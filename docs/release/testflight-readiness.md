# TestFlight readiness audit — what blocks an internal beta today

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

**Not yet uploadable.** Two hard blockers, one show-stopper bug for
LAN testers, plus a handful of nuisance gaps. No architectural
issues; no auth/networking rewrites required.

Estimated effort to first successful TestFlight upload: **~half a
day** of release-engineering work, almost all of it in Xcode + App
Store Connect rather than in the codebase.

---

## Hard blockers (must fix before first upload)

### 1. No signing configuration in `project.yml`

`project.yml` declares the bundle id and platform but does **not**
set `CODE_SIGN_STYLE` or `DEVELOPMENT_TEAM`. Every regenerated
Xcode project starts with signing unconfigured, which means:

- Archive → Distribute defaults to "Sign to run locally" rather
  than "App Store Connect distribution".
- Without a `DEVELOPMENT_TEAM`, automatic provisioning can't
  request a real distribution profile.

**Required:** add `CODE_SIGN_STYLE: Automatic` and
`DEVELOPMENT_TEAM: <Apple team id>` to the `DropStation` target's
`settings.base` in `project.yml`. Team id is the 10-character
string Apple shows under *Membership* in the developer portal.

### 2. No `NSLocalNetworkUsageDescription` in `Info.plist`

The app's entire purpose is talking to a Synology NAS on the
user's LAN (typically `192.168.x.x`, `10.x.x.x`, or `.local`
mDNS). iOS 14+ silently blocks connections to private subnets
until the user grants the "Local Network" permission — and that
prompt **only fires if `NSLocalNetworkUsageDescription` is in
`Info.plist`**.

Symptoms a beta tester would see today: app launches, login
spinner spins forever, no error. The OS-level block doesn't
surface as an `URLError`.

**Required:** add `NSLocalNetworkUsageDescription` with copy that
names what we're doing. Proposed wording:

> DropStation connects to your Synology NAS on your home or office
> network to manage your downloads.

---

## Nuisance gaps (fix before first upload to avoid repeated friction)

### 3. `ITSAppUsesNonExemptEncryption` not declared

Without this key, every TestFlight upload prompts an Export
Compliance questionnaire in App Store Connect. DropStation uses
only OS-standard HTTPS (`URLSession`, the system TLS stack) and
qualifies for the standard exemption.

**Required:** add `ITSAppUsesNonExemptEncryption = false` to
`Info.plist`. One-time fix; the upload flow then skips the prompt.

### 4. Marketing version out of sync with branch

`project.yml` has `MARKETING_VERSION: 0.5.0` and
`CURRENT_PROJECT_VERSION: 9`. The current branch
(`feature/0.5.2-active-state`) advertises 0.5.2 in `CHANGELOG.md`
and the commit message. A TestFlight build cut from this branch
would arrive labelled "0.5.0 (9)" — confusing for testers who can
see the changelog.

**Required:** bump `MARKETING_VERSION` to the version the next
build represents (e.g. `0.5.2`) and increment
`CURRENT_PROJECT_VERSION` per upload (App Store Connect rejects
duplicates).

### 5. CI is simulator-only

`.github/workflows/release.yml` builds an unsigned simulator `.app`
for proof-of-compile and explicitly does not produce an `.ipa`.
That's correct for the current "personal project, no Apple
account" posture but does **not** advance us toward TestFlight.

**Not blocking the first manual upload.** A signed CI workflow can
land later; for the first 2–3 betas, archiving + uploading from
the Xcode Organizer is faster than wiring up App Store Connect API
keys in GitHub secrets.

### 6. App icon tinted variant — visual sanity needed

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
  (no extra entitlement). Local Network is the only permission
  gap — see blocker #2.
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
  planned: 0.5.1 narrowed the blanket `NSAllowsArbitraryLoads` to
  `NSAllowsLocalNetworking` (cleartext HTTP on the LAN only) +
  delegate-based self-signed HTTPS trust, rather than per-domain
  exceptions (the NAS host is unknown ahead of time, so per-domain
  was never workable). No further ATS work expected before review.
- iPad-specific layout review. The target is universal
  (`TARGETED_DEVICE_FAMILY: "1,2"`), but UI was designed
  iPhone-first. Recommend recording the first TF group as
  iPhone-only until we deliberately review iPad behavior.
