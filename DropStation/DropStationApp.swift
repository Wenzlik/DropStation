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
        }
    }
}
