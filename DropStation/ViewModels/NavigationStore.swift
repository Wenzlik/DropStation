import Foundation
import SwiftUI

/// Tiny shared coordinator for the post-login tab shell. Lives at
/// the same level as `SessionStore` (injected as `@EnvironmentObject`
/// from `DropStationApp`) so any post-login surface can route the
/// user across tabs and pre-stage state on the destination.
///
/// Kept deliberately minimal — this is *not* a router framework.
/// Two state slots:
///
///   - `selectedTab` — drives the `TabView` selection binding in
///     `LoggedInShell`. Reads + writes from any view.
///   - `downloadsFilterRequest` — one-shot hint observed by
///     `TaskListView`. When the dashboard's "See all →" is tapped,
///     it sets `selectedTab = .downloads` and
///     `downloadsFilterRequest = .finished`; TaskListView's
///     `.onChange` consumes the value, applies it to its
///     view model's filter, and clears the slot so the next user-
///     driven filter change isn't undone.
@MainActor
final class NavigationStore: ObservableObject {
    enum Tab: Hashable {
        case dashboard
        case downloads
    }

    @Published var selectedTab: Tab = .dashboard
    @Published var downloadsFilterRequest: TaskFilter? = nil

    /// Shortcut: switch to the Downloads tab and pre-apply a filter.
    /// The downstream `TaskListView` consumes the filter and resets
    /// it to nil; the tab selection sticks as user state.
    func showDownloads(filter: TaskFilter) {
        downloadsFilterRequest = filter
        selectedTab = .downloads
    }
}
