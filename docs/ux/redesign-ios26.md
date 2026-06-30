# DropStation — iOS 26 Redesign Spec

> Status: **draft** · author: Product Designer pass · supersedes the
> execution (not the philosophy) of [`design-principles.md`](design-principles.md).
> This document is design language and screen direction only — no code,
> no architecture.

## Why a redesign

The app is technically clean but reads as **circa-2021**. The dated
signals, in priority order:

1. **Glassmorphism login card** (purple glow + heavy border) — a
   2020–2021 aesthetic, not iOS 26 Liquid Glass.
2. **Flat, fully-saturated blue rectangle buttons** — pre-iOS-26.
3. **All-caps tracked eyebrow labels everywhere** (OVĚŘENÍ, NEDÁVNO
   DOKONČENO, VZHLED, SOUKROMÍ) — an editorial pattern that now reads
   as a 2019 template.
4. **Ambiguous status iconography** — the same circular "↻" icon for
   completed *and* seeding tasks; colour does not disambiguate. The
   green dot + "Sdílení" repeats on every row → zero signal.
5. **Flat grey hero card** with weak hierarchy. The dominant metric is
   "75 — Aktuálně nečinné", i.e. *"nothing is happening"* set in a
   large font.
6. **Dense, undifferentiated list** in Downloads — a text table with
   decorative leading icons and no rhythm.
7. **Hand-reimplemented Settings** that approximates the native grouped
   list but drifts → uncanny-valley "almost native".
8. **Localization holes** — English strings inside the Czech UI
   ("Downloads", "Verify code", "6-digit code", "Remember password",
   "Default destination", English footers). Not a style issue, but it
   damages the sense of *finished* more than anything else.
9. **Inert-looking primary actions** — the "Přidat stahování" submit on
   Add task reads as a disabled field, and Task detail's pause/start
   actions are hidden in the "…" menu. Common actions don't look
   tappable or aren't on screen.

### Light vs dark

Light mode reads **noticeably more native** than dark — its grouped
cards on the system-grey background already look close to a native iOS
list. Dark mode's flat dark-grey cards are the weaker half and carry
most of the "old" feeling. The redesign should lift **dark mode**
hardest, while light mode mainly needs the status/CTA/localization
fixes rather than a structural overhaul.

## North star

**Stop painting custom chrome. Let the native iOS 26 system do the
work.** Liquid Glass ships for free on toolbars, tab bars, sheets,
buttons, and sidebars. Custom bordered/glowing cards go away. The
roadmap calls DropStation a "calm utility" — so content floats above
glass, decoration is minimal, signal is maximal.

Three principles that govern every screen below:

- **Content, not containers.** Fewer hairline-bordered cards, more air
  and typographic hierarchy.
- **Status = colour + shape, not text.** Downloading / seeding / done /
  paused / error must be legible in ~100 ms of peripheral vision.
- **Native components without make-up.** Settings = `Form`. Tab bar =
  system. Buttons = glass capsule.

---

# Foundations

## Material & depth

- Adopt the system **Liquid Glass** material for floating controls
  (toolbar buttons, the add/sort/filter cluster, tab bar, the login
  CTA). Let the system own the translucency, refraction, and specular
  edge — do **not** hand-roll glows or fake-glass gradients.
- **One primary surface per screen** still holds (from
  `design-principles.md`), but the primary surface should now be a
  *clean* glass or material surface, not a glowing card.
- Kill the purple ambient glow on the login card and the heavy
  custom borders. Background can stay a subtle dark gradient; it must
  not compete with content.
- Concentric corner radii: floating controls and sheets follow the
  device's concentric-radius rhythm rather than a single fixed 14/18.

## Colour & accent

Today there is no accent colorset — the app rides system blue plus
hardcoded values, while the logo is a purple→blue droplet.

- **Decided:** the accent is a **single clean blue** (the blue from the
  droplet — no purple in the UI). One named accent as the single source
  of truth, used sparingly: primary CTA, selected tab, interactive
  links. Not on every icon. The logo may keep its droplet shape but the
  UI accent stays mono-blue so it coexists cleanly with the semantic
  status colours below.
- Introduce **semantic status colours**, used *only* for status:
  - Downloading — accent / blue
  - Seeding — green
  - Paused — orange / yellow
  - Completed — secondary / neutral (a quiet ✓, not a loud colour)
  - Error — red
- Everything else is greyscale + material. Restraint is the brand.

## Typography

- Keep large navigation titles (they already feel iOS-native).
- Monospaced digits for all live numbers (speed, ETA, size, counts) —
  prevents jitter and reads "instrument panel".
- Retire the all-caps tracked eyebrow labels. Use native section
  headers (sentence case) where a label is genuinely needed; drop the
  label entirely where the section is self-evident.

## Status vocabulary (the core fix)

Each task maps to exactly one **(icon, shape, colour)** triple, and the
leading slot in any row is reserved for it — it is informative, never
decorative:

| State        | Icon (SF Symbol intent) | Colour    | Extra |
|--------------|-------------------------|-----------|-------|
| Downloading  | progress ring / arrow.down | accent | live % + thin progress sliver |
| Seeding      | arrow.up                | green     | up-speed |
| Paused       | pause.fill              | orange    | — |
| Completed    | checkmark               | neutral   | no sliver |
| Error        | exclamationmark.triangle| red       | badge, not dot |
| Queued       | clock / ellipsis        | secondary | — |

Reuse the existing `DSStatusDot` (ambient) vs `DSStatusBadge`
(exceptional) split from `design-principles.md` — but actually *honour*
it: dots for normal states, badges only for error/offline/reconnecting.

## Components evolution

- `DSCard` / `DSSectionCard` → thin out. Default to material + the
  existing hairline; reserve any "primary" glass treatment for the one
  hero surface per screen.
- `DSHeroCard` → re-spec around a *meaningful* primary metric (see
  Dashboard).
- `DSEyebrow` → deprecate or restyle to native section header.
- `DSProgressSliver` → keep; show only on active tasks, hide on
  completion (already the intent).
- `DSStatusDot` / `DSStatusBadge` → drive from the status vocabulary
  table above so colour/shape are consistent everywhere.

## Tab bar

- Replace the custom floating pill with the **native iOS 26 floating
  tab bar** (Přehled / Stahování). It gets Liquid Glass, the scroll
  behaviours, and the morph-to-search affordance for free, and stops
  looking "almost native".

---

# Screen-by-screen

## Login / 2FA  *(IMG_2094 — reviewed)*

Current: droplet logo in a glassy circle, glowing purple 2FA card,
all-caps "OVĚŘENÍ" eyebrow, plain text field, full-width solid blue
"Verify code" rectangle. Mixed EN/CZ.

Redesign:
- Remove the purple glow and heavy border. The card becomes a clean
  Liquid Glass / material surface, or even no card — just centred
  content on the gradient.
- Drop the "OVĚŘENÍ" eyebrow and the redundant shield-in-a-circle; the
  title "Zadejte 6místný kód" carries it.
- CTA → **glass capsule, prominent, accent-tinted**, not a full
  rectangle.
- Code field → large, monospaced, centred; consider segmented digit
  boxes for a more native verification feel.
- **Localize everything** ("6-digit code" → placeholder, "Verify code"
  → button).
- Logo: keep the droplet, but let it sit cleanly without the glassy
  halo ring.

## Dashboard / Přehled  *(IMG_2095 — reviewed)*

Current: large "Přehled" title, flat grey hero card with server name +
Online dot, dominant "75 Úlohy / Aktuálně nečinné", "10,25 TB free",
then "NEDÁVNO DOKONČENO" list with blue circular icons.

Redesign:
- **Fix the hero metric.** Three-state hierarchy for the dominant
  number:
  1. *Active* → aggregate **download speed** (large, monospaced) +
     count of active transfers.
  2. *Idle but queued* → nearest **ETA** or queued count.
  3. *Truly idle* → a calm "Vše dokončeno" state — never "75 idle" as
     the hero number.
- Hero surface → the one primary Liquid Glass surface; server identity
  (host + Online) sits as a quiet header inside it, free space as a
  secondary metric.
- "NEDÁVNO DOKONČENO" → native section header (sentence case). Rows use
  the **completed** status icon (quiet ✓), not the spinning-arrow that
  reads as "syncing".
- Consider making the hero interactive (tap speed → throughput sparkline;
  tap free space → storage breakdown) — Nice-to-have, not blocking.

## Downloads  *(IMG_2096 — reviewed)*

Current: "Downloads" title (un-localized), gear + sort/filter/add
cluster, dense rows: identical leading "↻" icon, two-line title, green
dot + "Sdílení" + size, chevron, hairline dividers. No visible progress.

Redesign:
- Localize the title.
- **Leading icon = status** (from the vocabulary table), so a glance
  down the list reads as a column of meaningful states, not identical
  spinners.
- Row hierarchy: title (smart-truncated — keep the informative head and
  tail, not a hard cut), then a single metadata line
  `status · speed/ETA · size` with monospaced numbers, then a thin
  progress sliver **only for active tasks**.
- De-emphasise the chevron; the whole row is the tap target.
- The sort/filter/add cluster → native Liquid Glass toolbar items.

## Settings / Nastavení  *(IMG_2097 — reviewed)*

Current: modal sheet, custom account card, custom grouped sections
imitating the native list, all-caps section headers, mixed EN/CZ
("Remember password", English footer).

Redesign:
- Rebuild on the **native grouped `Form`/`List`** with iOS 26 Liquid
  Glass. Instantly reads "correct iOS 26" and removes maintenance drift.
- Account block can stay a distinct header card (it's identity, it
  earns the prominence) — but cleaned up to native proportions.
- Section headers → native sentence-case.
- **Localize** the remaining EN strings and footers.
- Keep coloured SF Symbols in the leading slot (this is the one place
  the native Settings idiom *wants* colour).

## Task detail  *(reviewed — light)*

Current: Liquid-Glass-ish circular back / "…" buttons (these read fine
for iOS 26), a header card with the "↻" icon + title + green dot
"Sdílení", a "Přenos" section, then **nine stacked label–value rows**
(Size, Downloaded, Uploaded, ↓ Speed, ↑ Speed, Ratio, Peers, Seeders,
Leechers), then "Soubory (216)".

Problems:
- It's a **flat data dump**, not a hierarchy. Nine equal-weight rows
  bury what matters.
- **No visible primary actions.** Pause / resume / start / delete are
  hidden in the "…" menu → poor discoverability for the most common
  operations.
- **No progress visualization.** "Downloaded 2,79 GB / Size 2,79 GB" is
  100 % but the user has to do the math; an active task would have no
  visible bar at all.
- Same ambiguous "↻" status icon as the list.

Redesign:
- **Progress hero** at the top: a clear percentage/ring or bar, the
  status (from the vocabulary table), and live ↓/↑ speed in monospaced
  digits. This is the primary surface.
- **Primary action row** surfaced on-screen (e.g. Pause/Resume + Stop),
  not buried in "…". Destructive (Delete) stays in the overflow menu.
- **Group the metrics** into meaningful clusters instead of one flat
  list: *Transfer* (size / downloaded / uploaded / ratio) and *Swarm*
  (peers / seeders / leechers). Speeds belong in the hero, not as two
  more "—" rows.
- Files section keeps the skip/complete/downloading per-file hierarchy,
  driven by the same status colours.

## Add task / Nové stahování  *(reviewed — light)*

Current: "Zrušit" / "Nové stahování", an Odkaz / Soubor segmented
control, a "Soubor torrent" picker row, a "Cíl" destination row
("Default destination" — un-localized), and a **"Přidat stahování"
element that reads as a disabled placeholder field**, not a button.

Problems:
- **The primary CTA looks inert.** Grey text on a white card reads as a
  disabled text field — the user can't tell it's the submit button.
  This is the single worst affordance in the app.
- "Default destination" is **un-localized**.
- A lot of dead vertical space below the CTA; the sheet feels unfinished.

Redesign:
- Primary action → an unmistakable **glass capsule, accent-tinted,
  prominent button** ("Přidat") pinned bottom or directly under the
  fields; disabled state must look *disabled*, enabled must look
  *tappable*. Never ambiguous.
- Keep the native segmented control (it's fine).
- Localize "Default destination" → "Výchozí umístění".
- Tighten vertical rhythm so the sheet can be a compact
  `.medium`-height detent rather than a near-empty full screen.

## Active downloading state  *(no screenshot — owner has none; spec from principles)*

All captures are idle/seed, so the most important state — *something is
actively downloading* — is unverified in pixels. The redesign must make
this state shine, and it is the one to prototype first:
- **Dashboard hero** → live aggregate ↓ speed (large, monospaced) +
  active-transfer count as the dominant metric.
- **Downloads rows** → downloading status icon (accent), live
  `↓ speed · ETA` metadata, and the `DSProgressSliver` actually visible
  and animating.
- **Task detail** → progress hero filling, live ↓/↑ speed.
- Acceptance for this state can't be signed off until captured live —
  flag for a follow-up screenshot once a real download is running.

---

# Acceptance criteria

- No visible English string in the Czech localization.
- Every Downloads row communicates its state **without reading text**
  (icon colour + shape) within ~100 ms.
- The Dashboard hero shows a meaningful primary metric in all three
  states (active / queued / idle) — never "N idle" as the hero.
- Login and all primary buttons use native Liquid Glass capsules; no
  purple glow anywhere.
- Settings is indistinguishable from a native iOS 26 grouped list.
- All-caps eyebrow labels unified or removed across every screen.
- Every primary action looks tappable (honest enabled/disabled);
  common task actions (pause/resume/start) are on-screen, not buried.
- Task detail leads with a progress hero, not a flat metric list.
- Verified in **both** light and dark mode (dark mode lifted hardest).

# Open items / needed from product owner

- [x] Light-mode screenshots — received (Settings, Downloads, Detail, Add).
- [x] Task detail + Add task screenshots — received.
- [ ] Active-downloading capture still missing (owner has none right
      now) — sign-off on the active state defers until a live download
      can be screenshotted.
- [x] Accent decision — **single clean blue** (no purple in UI).
- [x] Sequencing decision — **start with the active-download state**
      across Dashboard + Downloads (core moment + currently unverified).
