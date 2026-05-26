# DropStation 0.5.0 - UI Review

## Overall assessment

DropStation no longer feels like a hobby SwiftUI utility project.

Version 0.5.0 introduces:
- cohesive visual language
- dashboard-first UX
- modern utility-app hierarchy
- stronger product identity

The app now resembles a real premium NAS companion app.

---

## Strongest areas

### Settings screen

Most product-ready screen in the app.

Strengths:
- account identity hero
- grouped sections
- restrained helper text
- clear hierarchy
- premium utility feel

---

### Dashboard

Strong visual direction.

Strengths:
- single dominant hero surface
- calm typography
- modern metrics presentation
- quick actions hierarchy
- native-feeling tab structure

---

### Downloads screen

Major improvement over legacy table-style UI.

Strengths:
- grouped activity-list feel
- thinner progress indicators
- calmer metadata
- improved density
- better consistency with dashboard

---

## Remaining weaknesses

### Idle-state wording

"0 KB/s / Working..." feels inconsistent when the NAS is idle.

Needs:
- explicit idle state
- intentional wording
- less "stuck process" feeling

---

### Light mode

Light mode lacks depth compared to dark mode.

Needs:
- slightly stronger surface separation
- improved contrast hierarchy

---

### Downloads density

Still slightly visually noisy with long torrent names.

Needs:
- calmer metadata
- lighter separators
- slightly improved hierarchy compression

---

## Product direction

DropStation should continue toward:

```text
premium native utility app
```

Not:
- analytics dashboard
- torrent-client skin
- overdesigned glassmorphism app

---

## Design principles to preserve

### One primary glass surface per screen

Keep:
- one dominant hero surface
- secondary surfaces restrained

Avoid:
- nested glass
- giant gradients
- excessive shadows

---

### Status hierarchy

Keep:

- DSStatusDot = ambient status
- DSStatusBadge = exceptional state

This significantly improves visual calmness.

---

## Strategic recommendation

Pause large-scale redesign work after 0.5.1.

Focus next on:
- feature depth
- usability
- App Store readiness
- reliability
- daily-use workflows

Avoid:
- endless visual redesign loops
- overengineering
- adding too many power-user systems too early
