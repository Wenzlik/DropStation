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
                    // When the user comes back from the Synology Secure SignIn app after
                    // approving a push, immediately retry the login instead of waiting
                    // for the next polling tick. iOS suspends the polling Task while we
                    // are backgrounded, so without this nudge the user would stare at
                    // the spinner for up to 5 s.
                    guard newPhase == .active, session.state == .twoFactorRequired else { return }
                    Task { await session.resendPushApproval() }
                }
        }
    }
}
