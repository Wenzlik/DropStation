import SwiftUI

@main
struct DropStationApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var navigation = NavigationStore()
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(navigation)
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
                .onChange(of: scenePhase) { _, phase in
                    // Foreground silent probe: every time the scene
                    // becomes active (cold launch, return from
                    // background, return from a sheet that briefly
                    // backgrounded us), throttled-revalidate the SID.
                    // The probe itself bails out instantly if it's
                    // been called recently or if we're not logged in,
                    // so this is safe to call indiscriminately.
                    if phase == .active {
                        Task { await session.probeIfStale() }
                    }
                }
        }
    }
}
