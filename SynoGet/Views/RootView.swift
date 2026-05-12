import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Restoring session…").foregroundStyle(.secondary)
                }
            case .loggedIn:
                TaskListView(session: session)
            case .loggedOut, .authenticating, .error:
                LoginView()
            }
        }
    }
}
