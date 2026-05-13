import SwiftUI

@main
struct DropStationApp: App {
    @StateObject private var session = SessionStore()
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(appearance.preferredColorScheme)
                .onOpenURL { url in
                    session.handleIncomingURL(url)
                }
                .task {
                    // Drives the launch-time session restore (saved SID probe →
                    // silent re-login → 2FA prompt → loggedOut). restoreOnLaunch
                    // is idempotent so this is safe if SwiftUI re-fires the task.
                    await session.restoreOnLaunch()
                }
        }
    }
}
