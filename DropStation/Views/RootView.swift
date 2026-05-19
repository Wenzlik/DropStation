import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                DSLoadingView("Restoring session…")
            case .loggedIn:
                LoggedInShell(session: session)
            case .connectionLost:
                ConnectionLostView()
            case .loggedOut, .authenticating, .twoFactorRequired, .validatingApiAccess, .sessionUnauthorized, .error:
                LoginView()
            }
        }
    }
}

/// Two-tab post-login shell: Dashboard (default) + Downloads (existing
/// list, untouched). Each tab owns its own `NavigationStack` so sheets
/// and pushed destinations stay scoped to one tab. The TabView
/// selection binds into `NavigationStore.selectedTab` so any post-
/// login surface can route the user across tabs — used by the
/// dashboard's "See all →" link into the Downloads tab.
private struct LoggedInShell: View {
    let session: SessionStore
    @EnvironmentObject private var navigation: NavigationStore

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            DashboardView(session: session)
                .tabItem {
                    Label("Dashboard", systemImage: "rectangle.grid.2x2")
                }
                .tag(NavigationStore.Tab.dashboard)
            TaskListView(session: session)
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .tag(NavigationStore.Tab.downloads)
        }
    }
}
