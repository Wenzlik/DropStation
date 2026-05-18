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
            case .loggedOut, .authenticating, .twoFactorRequired, .validatingApiAccess, .sessionUnauthorized, .error:
                LoginView()
            }
        }
    }
}

/// Two-tab post-login shell: Dashboard (default) + Downloads (existing
/// list, untouched). Each tab owns its own `NavigationStack` so sheets
/// and pushed destinations stay scoped to one tab.
private struct LoggedInShell: View {
    let session: SessionStore

    var body: some View {
        TabView {
            DashboardView(session: session)
                .tabItem {
                    Label("Dashboard", systemImage: "rectangle.grid.2x2")
                }
            TaskListView(session: session)
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
        }
    }
}
