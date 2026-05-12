import SwiftUI

@main
struct SynologyTorrentApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .onOpenURL { url in
                    session.handleIncomingURL(url)
                }
        }
    }
}
