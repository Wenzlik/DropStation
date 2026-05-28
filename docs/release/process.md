# Release process — dev installs vs TestFlight builds

Reference for the day-to-day question "what kind of build am I
making and what's it good for?" The repo today has three distinct
build flavors. They look similar in Xcode but have very different
properties.

---

## The three build flavors

### 1. Xcode-installed dev build (current default)

What you get when you hit ⌘R in Xcode against a tethered device.

- **Signing:** development cert (personal team or paid team).
- **Distribution:** none — only installs on devices registered
  to the signing identity, and only while Xcode does the install.
- **Lifetime on device:** 7 days on a free Apple ID, 1 year on a
  paid Developer Program team. App refuses to launch when the
  embedded provisioning profile expires.
- **OTA updates:** no. Every rebuild needs another tether.
- **Crash reports:** local-only (Xcode → Devices and Simulators →
  View Device Logs). Not surfaced in App Store Connect.
- **Right tool for:** active development, debugging, fast turnaround.
- **Wrong tool for:** daily personal use, anything someone else
  installs.

### 2. Simulator-only CI artefact (GitHub Actions release)

What `.github/workflows/release.yml` produces on a `v*.*.*` tag
push. A zipped, **unsigned** `.app` bundle.

- **Signing:** none (`CODE_SIGNING_ALLOWED=NO`).
- **Distribution:** GitHub Releases attachment.
- **Lifetime on device:** N/A — it doesn't install on real devices.
- **OTA updates:** N/A.
- **Crash reports:** none.
- **Right tool for:** proving the tagged commit compiles cleanly,
  letting someone load the build in the iOS Simulator without
  setting up Xcode.
- **Wrong tool for:** anything that involves a real iPhone.

### 3. TestFlight build (this phase's deliverable)

What you produce via Xcode → Product → Archive → Distribute App
→ App Store Connect, processed by Apple, then installed via the
TestFlight app on the tester's iPhone.

- **Signing:** distribution cert + App Store provisioning profile,
  both auto-managed.
- **Distribution:** App Store Connect → TestFlight, invited
  testers only.
- **Lifetime on device:** 90 days from upload date. After that
  the build is locked out and the tester needs a newer build.
- **OTA updates:** yes. New builds appear in TestFlight as soon
  as Apple finishes processing.
- **Crash reports:** automatic via App Store Connect's TestFlight
  → Crashes tab (no SDK needed). MetricKit-class hang and
  disk-write reports also surface there.
- **Right tool for:** daily personal use, friends-and-family beta,
  external closed beta, any case where the build needs to outlive
  a tether session.
- **Wrong tool for:** rapid feature iteration where you'd rebuild
  several times a day — too much processing wait time.

---

## Going from flavor 1 to flavor 3 (the part this phase is about)

See [`testflight-checklist.md`](testflight-checklist.md). High
level:

1. Add `CODE_SIGN_STYLE: Automatic` + `DEVELOPMENT_TEAM` to
   `project.yml`, regenerate the Xcode project.
2. Add `NSLocalNetworkUsageDescription` and
   `ITSAppUsesNonExemptEncryption` to `Info.plist`.
3. Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` when
   appropriate).
4. Archive in Xcode, distribute to App Store Connect, add to
   internal testing group.

The two `Info.plist` keys and the version bump are committed; the
team id and the actual archive step are user actions, not repo
changes.

---

## Day-to-day rhythm once TestFlight is live

For a single-maintainer project this should not become a
ceremony. Suggested cadence:

- **Active development → flavor 1 (Xcode install).** No
  TestFlight churn for in-flight work.
- **Once a feature group feels stable → flavor 3 (TestFlight).**
  Bump `CURRENT_PROJECT_VERSION`, archive, upload, share the
  build link with testers. Treat it as "promoting" the work to a
  wider audience, not as "shipping."
- **A release that warrants a CHANGELOG entry and a `v0.X.Y` tag →**
  cut the tag, let the simulator-smoke CI workflow run, also
  archive a TestFlight build under the same `MARKETING_VERSION`.
  The git tag is for the release; TestFlight is the
  distribution channel.

---

## CI signing (out of scope today, captured here for later)

The current `release.yml` workflow is deliberately unsigned; CI
TestFlight uploads need three secrets:

- App Store Connect API key (`.p8`), key id, issuer id.
- Distribution certificate (`.p12`) + import passphrase.
- App Store provisioning profile (`.mobileprovision`).

Wiring those into GitHub Actions secrets and adding an
`xcodebuild archive` + `xcrun altool --upload-app` step is a
half-day of work. **Don't do it until manual archive uploads
become an obvious bottleneck** — i.e. you find yourself archiving
more than once a week.

The right trigger to automate: when "ship a beta to TF" stops
being a deliberate decision and starts being something you'd do
on every push to `main`. Until then, manual is fine and gives
you a chance to look at every archive before it goes to testers.
