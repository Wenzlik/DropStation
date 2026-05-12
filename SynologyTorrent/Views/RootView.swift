import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            switch session.state {
            case .loggedIn:
                TaskListView(session: session)
            case .loggedOut, .authenticating, .error:
                LoginView()
            }
        }
    }
}
