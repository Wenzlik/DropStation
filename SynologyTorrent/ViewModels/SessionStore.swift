import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case loggedOut
        case authenticating
        case loggedIn
        case error(String)
    }

    @Published private(set) var state: State = .loggedOut
    @Published private(set) var config: ServerConfig = ServerConfigStore.load() ?? .default
    @Published var pendingMagnetLink: String?

    let client = SynologyAPIClient()

    func login(config: ServerConfig, password: String, otpCode: String? = nil) async {
        self.config = config
        guard let url = config.baseURL else {
            state = .error("Invalid server URL.")
            return
        }
        await client.configure(baseURL: url)
        state = .authenticating
        do {
            try await client.login(account: config.account, password: password, otpCode: otpCode)
            ServerConfigStore.save(config)
            try? KeychainStorage.setPassword(password, for: config.account)
            state = .loggedIn
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func logout() async {
        try? await client.logout()
        state = .loggedOut
    }

    /// Handle magnet: links opened from outside the app.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "magnet" else { return }
        pendingMagnetLink = url.absoluteString
    }
}
