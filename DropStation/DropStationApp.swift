import SwiftUI

@main
struct DropStationApp: App {
    @StateObject private var session: SessionStore
    @StateObject private var navigation: NavigationStore
    @StateObject private var taskStore: DownloadTaskStore
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Explicit init so DownloadTaskStore can capture the
        // session's client + a weak-session handleUnauthorized
        // hook. StateObject's autoclosure-default form can't
        // reference a sibling property's value during property
        // initialization, but the explicit wrappedValue form lets
        // us build the dependency graph deterministically.
        let session = SessionStore()
        let navigation = NavigationStore()
        let store = DownloadTaskStore(
            client: session.client,
            onUnauthorized: { [weak session] reason in
                Task { @MainActor in
                    session?.handleUnauthorized(reason: reason)
                }
            }
        )
        _session = StateObject(wrappedValue: session)
        _navigation = StateObject(wrappedValue: navigation)
        _taskStore = StateObject(wrappedValue: store)
    }

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(navigation)
                .environmentObject(taskStore)
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
