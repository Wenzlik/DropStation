# iPhone Duo / wide windows

iPhone Duo (iOS 27.1) has two displays, both `userInterfaceIdiom == .phone`:

- **Outer** (~466 × 678 pt): compact width → today's iPhone layout, unchanged.
- **Inner** (~669 × 951 pt): regular width **and** regular height → wide layout.

## The rule

`DSLayout.isWide` (`DesignSystem/LargeWindow.swift`): horizontal **and** vertical
size class regular. Never the idiom or device model. Every non-hinged iPhone has
one compact axis (iPhone Max landscape is regular × compact), so iPhones never
change. iPad is wide too — intended.

## Per screen

| Screen | Wide window | Otherwise |
| --- | --- | --- |
| Downloads | `SplitPanes`: list (leading) + `TaskDetailView` (trailing). iOS 27.1: `ArrangementView` `.split` around the fold; older OS / Xcode 26: `HStack` (list 320–440 pt). Needs ≥ 1 task; an empty / first-load list stays one centred column. | `NavigationStack(path:)` push, as before |
| Dashboard | One column capped at 600 pt, centred | unchanged |
| Add download, Settings, folder picker, bug report, What's new, web sign-in | Form capped at 600 pt, background full width | unchanged |
| Sign-in, Certificate trust | already capped at 520 pt | unchanged |
| Connection lost | capped at 600 pt | unchanged |

Every full-window screen and each split pane has `avoidsReservedRegions()`:
active `ReservedRegion`s (`.occlusion` = Duo's side status column, `.division` =
the fold) become safe-area padding. A region at an edge pads that edge. A fold
through the middle of a full-window screen moves the content onto the larger
half (the leading one, or the top one in tabletop, when the halves are equal).
Any part the safe area already covers is not padded twice. The rule is the pure
`ReservedEdgeInsets`, unit-tested in `ReservedEdgeInsetsTests`.

## Selection and fold / unfold

`TaskListView` keeps one `@State path: [DownloadTask]`:

- Compact: the navigation path (a tap pushes, as before).
- Two panes: a tap **replaces** `path` with `[task]`. It never appends, so
  nothing stacks. The trailing pane shows `path.last` while it's still listed,
  otherwise the first listed task. That fallback is never written into `path`.
- **Fold** after picking a task → that task's detail, pushed once. Fold with only
  the default first-task selection → the list. Nothing was opened, so nothing
  is pushed.
- **Unfold** with a detail pushed → that task is selected in the two panes.
- A pick that is deleted or cleared is dropped from `path` in either layout,
  so deleting the last task (which ends two-pane) or folding never pushes a
  task that's gone. Only two panes also drop a pick the filter hides (they
  fall back to the first task); compact keeps a pushed detail open after its
  task leaves the filter, as before.
- The tab selection lives in `NavigationStore`, so a fold doesn't change it.
  Sheets and alerts hang off a view that stays put through the layout switch,
  so an open Add sheet survives a fold.
- Each layout has its own `List`, so the rows on screen are remembered per
  layout (`onScrollVisibilityChange`) and the new list scrolls to the topmost
  of them when it appears after a fold/unfold. A pop back or a plain iPhone
  never scrolls. The detail's scroll position still resets (it is rebuilt per
  layout); unverified on hardware.

## Compile guards

Every iOS 27.1 symbol is behind `#if compiler(>=6.4)` (Xcode 26 / Xcode Cloud)
**and** `if #available(iOS 27.1, *)`. The deployment target stays iOS 26.0.
Xcode 27.0 (Swift 6.4, no 27.1 SDK) would not compile those blocks. It isn't
used for DropStation.

## Simulator / device checklist (owed)

1. Duo outer, portrait + landscape: identical to an iPhone. Nothing under the
   side status column.
2. Duo inner, portrait + landscape: Downloads shows list + detail, the first
   task is selected, a tap changes the detail, and the selected card has an
   accent ring.
3. Fold with a picked task → its detail, pushed once. Back → list. Unfold →
   same task selected.
4. Delete or clear the selected task in two panes → the detail moves to the
   first task. No crash.
5. Tabletop (partiallyOpen): no text or control in the fold band.
6. Dashboard, Settings, Add download on inner + iPad: centred, not edge to
   edge.
7. iPad full screen + Split View narrow (compact → push layout). iPhone Max
   landscape is unchanged.
8. Fold with Add download open: the sheet stays and the typed URL is kept.
