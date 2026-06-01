# TestFlight release notes template

Reusable shape for the per-build "What to Test" notes that
TestFlight shows to testers when they tap a build. Keep them
short, user-facing, and tied to what a tester can actually
observe — don't paste a commit log.

---

## Template

Copy the block below, fill in the brackets, paste into App Store
Connect → TestFlight → *(build)* → Test Details → What to Test.

```
DropStation [version] (build [build]).

What changed:
• [user-visible change #1, one short sentence]
• [user-visible change #2]
• [user-visible change #3]

What to focus on this build:
• [the specific thing you want validated — e.g. "Adding a magnet link with Czech characters in the name" or "Background → foreground transitions on cellular"]

Known issues:
• [anything you already know is broken, so testers don't refile it]
• [or "none known" if there are none]

Report bugs via Settings → Report a bug.
```

Hard limits: 4000 characters total, but aim for under 600 — testers
read past the third bullet on a phone screen and no further.

---

## Worked example

For the next build after the current `0.5.3` build `15`:

```
DropStation 0.5.3 (build 16).

What changed:
• [one user-visible fix or improvement since build 15]
• [second tester-visible change]
• [third tester-visible change, if any]

What to focus on this build:
• Regression-check login, certificate trust, Active now, and Settings → Report a bug.
• Czech locale walkthrough — Settings → DropStation → Language → Čeština and verify no buttons wrap or truncate.
• [specific risky change from this build]

Known issues:
• Plural rules for `%lld file` not yet wired — Czech builds render the singular form for all counts.
• iPad layout not yet reviewed — iPhone only for this beta.
• No background refresh; task list updates only while the app is open.

Report bugs via Settings → Report a bug.
```

---

## Style rules

These keep notes useful in the wild and prevent drift toward
commit-log noise:

1. **Subject of every bullet is the user, not the code.** "Tapping
   X now does Y" — never "refactored Z module."
2. **No file paths, no class names, no API names.** A tester
   reading this doesn't know what `DownloadTaskStore` is.
3. **Three bullets max in "What changed."** If you have more,
   group them or roll the lesser ones into a "smaller fixes:" tail.
4. **Always include "What to focus on this build."** This is the
   feedback prompt — if you don't ask for something specific,
   you get vague feedback or none.
5. **Known issues stay until they're fixed.** Don't drop a known
   issue from notes between builds; tracking it across builds
   tells testers you're aware. Drop the bullet the build *after*
   the fix ships.
6. **No emojis.** Project house style is plain text. Tone is
   calm-utility, not energetic-launch.
7. **End with the bug-report pointer.** Testers forget it exists
   otherwise.

---

## What goes elsewhere

- **Architecture / refactoring notes** → commit body. Testers
  don't need these; reviewers reading the code do.
- **Detailed feature design notes** → `docs/next-steps/<version>.md`.
- **User-facing changelog for the App Store / Settings → What's New** →
  `CHANGELOG.md`. The same release usually warrants a CHANGELOG
  entry; the TF notes are a tighter "this build" cut of that
  entry, focused on what to validate.
- **Breaking changes / migration steps** → none today (single-
  user app, no backend). If we ever add an account, those go in
  `CHANGELOG.md` with a `### Breaking` block.
