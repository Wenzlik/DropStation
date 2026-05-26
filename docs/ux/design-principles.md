# DropStation - Design Principles

## Philosophy

DropStation is a premium native utility app for Synology Download Station.

The product should feel:
- calm
- reliable
- native
- fast
- tactile
- information-dense
- intentionally restrained

Not:
- flashy
- over-animated
- dashboard-heavy
- crypto-inspired
- overdesigned

The goal is:
```text
premium NAS companion
```

Not:
```text
torrent power-user kitchen sink
```

---

# Visual language

## One primary surface per screen

Each screen may contain:
- one dominant `.primary` glass surface

All secondary surfaces should use:
- `.regularMaterial`
- restrained borders
- subtle hierarchy

Avoid:
- nested glass
- giant gradients
- excessive translucency
- multiple competing hero cards

---

# Status hierarchy

## DSStatusDot

Used for:
- ambient status
- normal operational state

Examples:
- Online
- Downloading
- Seeding
- Paused
- Completed

Goal:
- calm status communication

---

## DSStatusBadge

Used only for:
- exceptional states
- warning states
- transitional states

Examples:
- Offline
- Error
- Reconnecting
- Experimental
- Beta

Goal:
- avoid visual noise
- preserve hierarchy
