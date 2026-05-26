# Roadmap — quick reference

This file is a discoverable entry point. The full roadmap, with
philosophy, priorities, and the per-bucket breakdown, lives in
[`docs/roadmap/ROADMAP_V2.md`](docs/roadmap/ROADMAP_V2.md) — that is
the single source of truth for product direction.

## Product direction

DropStation is evolving into a **premium native NAS companion** for
Synology Download Station — not a torrent-client kitchen sink.

Priority: clarity, reliability, speed, native feel, calm utility UX.

## Current focus (0.5.1)

Stabilization + shared infrastructure after the 0.5.0 dashboard +
design-system release. No new redesigns, no architecture rewrites.

In flight or shipped on `main`:

- ✅ Dashboard hero three-way state (no more "0 KB/s Working…")
- ✅ Downloads list readability polish
- ✅ Light-mode hairline contrast
- ✅ Settings destructive-action toned down
- ✅ Placeholder Quick Actions removed
- ✅ `DownloadTaskStore` — shared task layer
- ⏳ Real free-disk space via `SYNO.FileStation.Info`
- ⏳ Self-signed certificate UX
- ⏳ Test coverage + foreground-probe verification
- ⏳ Localization foundation (`Localizable.strings` + Czech)

See [`docs/next-steps/0.5.1-polish.md`](docs/next-steps/0.5.1-polish.md)
for the planning detail.

## Beyond 0.5.1

Daily usability (Share Extension, notifications, multi-server,
richer task detail), then distribution (App Store readiness,
localization, accessibility, TestFlight). Power-user features
(RSS, widgets, automation) stay behind stability + App Store
readiness.

Full breakdown: [`docs/roadmap/ROADMAP_V2.md`](docs/roadmap/ROADMAP_V2.md).

## Other docs

- [`docs/ux/design-principles.md`](docs/ux/design-principles.md) —
  visual language rules (DSStatusDot ambient / DSStatusBadge
  exceptional, one primary glass per screen, …).
- [`docs/reviews/`](docs/reviews/) — UI review notes per release.
- [`docs/releases/`](docs/releases/) — release-level summaries.
- [`docs/next-steps/`](docs/next-steps/) — work tracking for the
  next release.
- [`CHANGELOG.md`](CHANGELOG.md) — short user-facing changelog
  (bundled into the app's Settings → Version → What's new).

## Maintenance

When implementation diverges from these docs, the docs change
first — not chat history, not commit messages. See
[`AGENTS.md`](AGENTS.md) for the contributor workflow.
