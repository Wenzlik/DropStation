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

---

## Release-engineering log

Short incident log so future contributors can `git blame` an
older tag or weird-looking commit and find the *why*. Reverse
chronological; only entries worth remembering.

### v0.5.3 tag — premature cut

**Symptom.** `v0.5.3` is on commit `b6af516`. That commit's
`project.yml` says `MARKETING_VERSION = 0.5.2`,
`CURRENT_PROJECT_VERSION = 14`. The actual 0.5.3 / 15 identity
landed one commit later (PR #14 → `main`).

**How it happened.** During the Czech-localization batch
(PRs #11 / #12 / #13), the workflow was to stack changes on
`work/localization-foundation` and merge in one go. A
version-bump + docs commit (`e328d03`) was pushed onto the
branch after PR #13 had already been clicked-to-merge in the
web UI — GitHub's merge built off the PR's head ref as of the
"Merge" click, missing the new push by seconds.

The branch was then deleted as routine cleanup (without
verifying `git log origin/<branch> ^origin/main` was empty),
which orphaned `e328d03`. The `v0.5.3` tag was cut on
`b6af516` before the gap was noticed. The commit survived
locally as a dangling object in the reflog; a rescue cherry-
pick (commit `f8e76ea`) and PR #14 brought the version bump
to `main`.

**Decision: tag left in place.** Per the `refs/tags/v*`
ruleset, the tag is immutable without a manual bypass. Options
were (a) live with it, (b) bypass the ruleset to move the tag,
(c) skip and cut `v0.5.4` later. Option (a) was chosen because
the consequences are bounded:
- The `release.yml` artifact attached to the v0.5.3 GitHub
  Release is a *simulator-only smoke build*. It's not a
  distribution channel; it's a reproducible-build proof for
  the tagged commit.
- Real TestFlight builds come from Xcode Cloud against the
  current `main` HEAD, which carries the correct 0.5.3 / 15
  identity. The cs-bilingual binary that lands in testers'
  TestFlight apps is fine.
- The mismatch only matters to anyone running
  `git checkout v0.5.3` and inspecting `project.yml` — which
  is rare enough that one HTML comment in `CHANGELOG.md` and
  this entry are sufficient signposting.

**Prevention.** Two rules added for future releases:
1. Before deleting a feature branch on origin after a PR
   merges, verify `git log origin/<branch> ^origin/main`
   outputs nothing.
2. Do not cut a release tag in the same minute as the
   release-PR merge. Pull `main`, `git log -3`, eyeball the
   `project.yml` / `CHANGELOG.md` identity, *then* tag.

Both are now in the `AGENTS.md`-adjacent claude-memory store so
they survive into future agent sessions.

