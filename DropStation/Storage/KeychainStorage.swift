import Foundation
import Security

/// Minimal Keychain wrapper. Stores two classes of items keyed under one service:
///   - Password   (account = NAS username)
///   - SID        (account = "<username>@<host>")
/// Items are tagged by Keychain "label" so the same NAS username can have
/// distinct entries for password vs sid without colliding.
enum KeychainStorage {
    private static let service = "com.wenzlik.DropStation"

    enum Kind: String {
        case password = "password"
        case sid = "sid"
    }

    // MARK: - Password

    static func setPassword(_ password: String, for account: String) throws {
        try store(value: password, kind: .password, account: account)
    }

    static func password(for account: String) -> String? {
        load(kind: .password, account: account)
    }

    static func deletePassword(for account: String) {
        remove(kind: .password, account: account)
    }

    // MARK: - SID

    static func setSID(_ sid: String, for accountAtHost: String) throws {
        try store(value: sid, kind: .sid, account: accountAtHost)
    }

    static func sid(for accountAtHost: String) -> String? {
        load(kind: .sid, account: accountAtHost)
    }

    static func deleteSID(for accountAtHost: String) {
        remove(kind: .sid, account: accountAtHost)
    }

    // MARK: - Common

    private static func store(value: String, kind: Kind, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: kind.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        var attrs = query
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    private static func load(kind: Kind, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: kind.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func remove(kind: Kind, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: kind.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case status(OSStatus)
    }
}
