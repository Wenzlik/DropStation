# TestFlight action checklist — internal beta maintenance

> Companion to [`testflight-readiness.md`](testflight-readiness.md)
> (the diagnosis) and [`testflight-rollout.md`](testflight-rollout.md)
> (the rollout plan + metadata). This file is the **ordered task
> list**: top to bottom, each step is a discrete piece of work
> that either lives in the repo or in App Store Connect.

Current state: internal TestFlight is live across the
`0.5.2 → 0.5.3` line. Current repo checkpoint is build `15` —
the first bilingual (en + cs) release. This checklist now tracks
what remains to validate and repeat for future TestFlight
uploads.

---

## Phase 1 — Prerequisites (outside the repo)

These don't touch source; they unblock everything that follows.

- [x] **Active Apple Developer Program membership** ($99/yr) on the
      Apple ID you intend to ship from. Confirm under
      <https://developer.apple.com/account> → *Membership*.
- [x] **Capture your team id** (10-character alphanumeric string)
      from that same Membership page. Use it in Phase 2 only if
      you decide to codify signing in `project.yml`.
- [x] **Register the bundle id** `com.wenzlik.DropStation` under
      *Certificates, Identifiers & Profiles → Identifiers → App IDs*.
      No special capabilities to enable (push, sign-in-with-apple,
      etc.) — DropStation needs none of those today.
- [x] **Create the app record** in App Store Connect:
      *My Apps → ＋ → New App*. Platform iOS, bundle id from above,
      SKU = `dropstation`, primary language English. Don't fill
      marketing copy yet — that comes in [`testflight-rollout.md`](testflight-rollout.md).
- [x] **Set up an internal testing group** in App Store
      Connect → *TestFlight → Internal Testing*. Add yourself first
      so the first upload has a destination.

---

## Phase 2 — Codebase preparation

These are repo-side. Most are mechanical; the ones marked
**(user)** need your input.

- [x] **`Info.plist`: `NSLocalNetworkUsageDescription`** —
      committed via this audit. Confirms the OS-level Local
      Network prompt actually fires on first NAS connection.
- [x] **`Info.plist`: `ITSAppUsesNonExemptEncryption = false`** —
      committed via this audit. Eliminates the Export Compliance
      questionnaire on every upload.
- [x] **`project.yml`: version bump** — `MARKETING_VERSION` and
      `CURRENT_PROJECT_VERSION` updated to match the branch.
- [ ] **Optional repo-side signing config** *(user)* — if you want
      regenerated projects to archive without manual Xcode signing
      selection, add to the `DropStation` target:
      ```yaml
      CODE_SIGN_STYLE: Automatic
      DEVELOPMENT_TEAM: <your 10-char team id>
      ```
      Then `xcodegen generate` to regenerate the project. The
      placeholder block is already present in `project.yml` —
      uncomment and fill in your team id. This is no longer a
      blocker because the manual Xcode signing path has already
      produced TestFlight builds.
- [ ] **`xcodegen generate`** after every `project.yml` change.
      Don't commit `DropStation.xcodeproj` (still gitignored).
- [x] **Confirm `CURRENT_PROJECT_VERSION` bumps per upload.**
      App Store Connect rejects duplicate build numbers within a
      version. Adopt: bump `CURRENT_PROJECT_VERSION` (e.g. 10 → 11)
      every time you archive a build for TestFlight, even if
      `MARKETING_VERSION` hasn't changed. Current repo build is
      `13`; the next TestFlight archive should bump to `14`.

---

## Phase 3 — First archive / upload

The first TestFlight upload is proven. Keep the local Xcode
Organizer steps below for manual uploads; if the build is produced
by Xcode Cloud instead, the physical-device setup items do not
apply.

- [ ] **Plug in (or pair) a physical iPhone** *(manual archive
      only)*. Required to build
      with the *Any iOS Device (arm64)* destination — the only
      destination Xcode accepts for archiving.
- [ ] **Select scheme `DropStation`, destination *Any iOS Device
      (arm64)* *(manual archive only)*.**
- [x] **Produce an archive for App Store Connect.** First archive on a fresh machine may
      take 3–5 minutes; Xcode will also request a Distribution
      certificate the first time (let it auto-create).
- [x] **Distribute/upload to App Store Connect.**
      Pick *Automatic signing*. If Xcode shows a provisioning
      profile error, *Manage* → *Modify* → *Automatically manage
      signing*, then retry.
- [x] **Wait for "processing" email** from App Store Connect
      (5–60 minutes). The build appears in
      *App Store Connect → TestFlight → iOS Builds* once
      processing finishes.
- [x] **Add the new build to your internal testing group.** First
      build per version triggers an export compliance step (the
      `ITSAppUsesNonExemptEncryption = false` from Phase 2 makes
      it a no-op).

---

## Phase 4 — First install on a real device

Confirms the build actually runs end-to-end on TestFlight. Do not
mark these done unless the installed TestFlight build has been
checked on a real device.

- [ ] **Install TestFlight** from the App Store on the test
      device if not already present.
- [ ] **Accept the internal-tester invite** (email from App Store
      Connect; arrives within ~1 minute of adding yourself to the
      group).
- [ ] **Install the build via TestFlight.**
- [ ] **First launch validation:**
  - [ ] Launch screen appears, app opens to login screen.
  - [ ] iOS prompts for *Local Network* permission on the first
        attempt to reach the NAS — confirms `NSLocalNetworkUsageDescription`
        copy reads cleanly to a stranger.
  - [ ] Login → 2FA → task list works on a real device against a
        real NAS over Wi-Fi.
  - [ ] Background the app, foreground it again, confirm session
        survives.
  - [ ] Force-quit the app, relaunch, confirm session restores
        without prompting for OTP.

---

## Phase 5 — Smoke checklist before sharing the build with anyone else

Tick all of these on the installed TF build before sending the
invite to another person:

- [ ] **Cold start with no saved config** (install fresh, delete
      app first) → login screen, no crash.
- [ ] **Cold start with saved config** → task list, no OTP prompt
      unless DSM actually expired the session.
- [ ] **Add download** via URI works.
- [ ] **Add download** via `.torrent` file picker works.
- [ ] **Magnet hand-off from Safari** opens DropStation.
- [ ] **Switch Wi-Fi off mid-session** → "Connection lost" card
      appears; switching Wi-Fi back on auto-recovers without user
      tap.
- [ ] **In-app bug report** → mail composer opens with subject +
      body filled (or clipboard fallback fires; see the Mailto
      regression test added in 0.5.2).
- [ ] **No debug output in Console.app** when device is attached
      and the app is running (`DSLog` should be silent in Release).
- [ ] **Switch language to Czech** in Settings → DropStation →
      Language (or set iOS system language to Czech). Re-launch
      the app, confirm login / dashboard / downloads / settings
      / bug report all render in Czech and no button label
      wraps or truncates under the longer translations.

---

## Phase 6 — When ready, expand the testing group

Out of scope for the first build; covered in
[`testflight-rollout.md`](testflight-rollout.md). Briefly: don't
expand the group until the smoke checklist passes on at least one
physical device, ideally two (one yours, one on someone else's
network you can reach by message for triage).

---

## Reference — what each Info.plist key does for us

For the next person reading `Info.plist` cold:

| Key | Why |
|-----|-----|
| `NSLocalNetworkUsageDescription` | iOS 14+ requires this to allow connections to RFC 1918 / `.local` addresses. Without it, NAS connections silently fail. |
| `ITSAppUsesNonExemptEncryption` | Declares the app qualifies for the standard HTTPS-only encryption export exemption. Skips the per-upload Export Compliance questionnaire. |
| `NSAllowsLocalNetworking` | Allows cleartext HTTP to a LAN NAS (`.local` / RFC 1918 host with HTTPS disabled). Replaced the blanket `NSAllowsArbitraryLoads` in 0.5.1. **Self-signed HTTPS is NOT handled here** — `NSAllowsArbitraryLoads` never trusted self-signed certs either; that's the `ServerTrustCoordinator` URLSession delegate's job (trust-on-first-use + pinning). The delegate's `.useCredential` overrides ATS cert-chain checks, so HTTPS (valid or pinned-self-signed) works under full ATS. |
| `CFBundleURLTypes (magnet)` | Lets Safari hand magnet links to us. |
| `UISupportedInterfaceOrientations` | iPhone orientations — portrait + both landscapes. UI is designed portrait-first but tolerates landscape. PortraitUpsideDown intentionally omitted on iPhone (Face ID phones don't benefit). |
| `UISupportedInterfaceOrientations~ipad` | iPad orientations — all four (portrait, upside-down, both landscapes). App Store Connect rejects builds (ITMS-90474) without all four because of iPad multitasking. Required as long as `TARGETED_DEVICE_FAMILY` includes `2` (iPad). |
| `UILaunchScreen` | Empty dict = default solid-background launch screen. Intentional; no decorative launch art yet. |

---

## Reference — Xcode Cloud bootstrap

Xcode Cloud workflows (e.g. *Archive - iOS* on the Default
workflow) expect to find `DropStation.xcodeproj` at the repo root
immediately after cloning. This project's `.xcodeproj` is
gitignored — generated from `project.yml` by XcodeGen — so a
fresh clone has no project file and the cloud build fails with:

```
Project DropStation.xcodeproj does not exist at the root of the
repository
```

Fix: `ci_scripts/ci_post_clone.sh` (checked in at the repo root).
Xcode Cloud runs `ci_scripts/ci_post_clone.sh` automatically after
cloning the source. The script installs XcodeGen via Homebrew
(preinstalled on Xcode Cloud workers) and runs `xcodegen generate`,
producing the `.xcodeproj` before the Archive action runs.

Touchpoints:

  - `ci_scripts/ci_post_clone.sh` — the bootstrap script. Must be
    executable (`chmod +x`), shellcheck-clean, and idempotent.
  - The script uses `$CI_PRIMARY_REPOSITORY_PATH` to navigate to
    the repo root — Xcode Cloud sets this env var on every build.
  - Sanity-checks that `DropStation.xcodeproj` exists at the end
    and exits non-zero otherwise; saves a confusing "project does
    not exist" later in the workflow.

Local archives don't need this — developers run `xcodegen generate`
themselves before opening Xcode (the same step `README.md` calls
out in the Installing section). The script exists specifically
because the Xcode Cloud sandbox has no convenient hook for a
developer to run an extra command before the workflow's first
Xcode invocation; `ci_post_clone.sh` is that hook.
