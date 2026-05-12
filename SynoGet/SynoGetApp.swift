import SwiftUI

@main
struct SynoGetApp: App {
    @StateObject private var session = SessionStore()
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

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
                .onChange(of: scenePhase) { _, newPhase in
                    // When the user comes back from the Synology Secure SignIn app
                    // after approving the push, immediately retry the login instead
                    // of waiting for them to tap the button.
                    guard newPhase == .active, session.state == .twoFactorRequired else { return }
                    Task { await session.retryAfterPushApproval() }
                }
        }
    }
}
