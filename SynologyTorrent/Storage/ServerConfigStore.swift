import Foundation

/// Persists the non-sensitive parts of `ServerConfig` (host/port/account) in UserDefaults.
/// The password is stored separately in Keychain via `KeychainStorage`.
enum ServerConfigStore {
    private static let key = "synology.server.config"

    static func load() -> ServerConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ServerConfig.self, from: data)
    }

    static func save(_ config: ServerConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
