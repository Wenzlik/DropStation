import Foundation
import Security

/// Minimal Keychain wrapper. Stores four classes of items keyed under one service:
///   - Password    (account = NAS username)
///   - SID         (account = "<username>@<host>")
///   - Cookies     (account = "<username>@<host>", JSON-encoded [StoredCookie])
///   - SessionMeta (account = "<username>@<host>", JSON-encoded SessionMetadata)
/// Items are tagged by Keychain "label" so the same NAS username can have
/// distinct entries without colliding.
enum KeychainStorage {
    private static let service = "com.wenzlik.DropStation"

    enum Kind: String {
        case password = "password"
        case sid = "sid"
        case cookies = "cookies"
        case sessionMeta = "sessionMeta"
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

    // MARK: - Cookies

    /// Persist the Secure SignIn web session cookies. JSON-encoded so the
    /// generic password storage primitive keeps working. Encoding errors
    /// surface as `KeychainError.encoding` rather than crashing — a
    /// cookie that can't be encoded just means session restore won't be
    /// available next launch, not that the current session breaks.
    static func setCookies(_ cookies: [StoredCookie], for accountAtHost: String) throws {
        do {
            let data = try JSONEncoder().encode(cookies)
            guard let json = String(data: data, encoding: .utf8) else {
                throw KeychainError.encoding
            }
            try store(value: json, kind: .cookies, account: accountAtHost)
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.encoding
        }
    }

    static func cookies(for accountAtHost: String) -> [StoredCookie]? {
        guard let json = load(kind: .cookies, account: accountAtHost),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([StoredCookie].self, from: data)
    }

    static func deleteCookies(for accountAtHost: String) {
        remove(kind: .cookies, account: accountAtHost)
    }

    // MARK: - Session metadata

    /// Persist sidecar info (createdAt / lastValidatedAt / sessionName) for
    /// the SID under the same account-at-host key. JSON-encoded for the
    /// generic password slot. Encoding failures surface as
    /// `KeychainError.encoding` — the SID itself is unaffected, we just
    /// lose the staleness hint and the next launch will run a fresh
    /// validation probe regardless.
    static func setSessionMetadata(_ metadata: SessionMetadata, for accountAtHost: String) throws {
        do {
            let data = try JSONEncoder().encode(metadata)
            guard let json = String(data: data, encoding: .utf8) else {
                throw KeychainError.encoding
            }
            try store(value: json, kind: .sessionMeta, account: accountAtHost)
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.encoding
        }
    }

    static func sessionMetadata(for accountAtHost: String) -> SessionMetadata? {
        guard let json = load(kind: .sessionMeta, account: accountAtHost),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SessionMetadata.self, from: data)
    }

    static func deleteSessionMetadata(for accountAtHost: String) {
        remove(kind: .sessionMeta, account: accountAtHost)
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
        case encoding
    }
}
