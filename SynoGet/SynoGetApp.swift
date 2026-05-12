import SwiftUI

@main
struct SynoGetApp: App {
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
