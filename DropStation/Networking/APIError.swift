import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case notLoggedIn
    case http(Int)
    case decoding(Error)
    case synology(code: Int, message: String)
    case transport(Error)
    /// The NAS presented a certificate that doesn't validate against
    /// the system trust store and isn't pinned — the signature of a
    /// self-signed DSM certificate the user hasn't trusted yet.
    /// Carries the host and the leaf's SHA-256 fingerprint so the UI
    /// can show it and offer to trust (pin) it. Distinct from a
    /// transient connectivity blip: retrying won't help until the
    /// user decides.
    case serverTrust(host: String, fingerprint: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid server URL.")
        case .notLoggedIn:
            return String(localized: "Not logged in.")
        case .http(let code):
            return String(localized: "HTTP error \(code).")
        case .decoding(let err):
            return String(localized: "Decoding error: \(Self.describe(decodingError: err))")
        case .synology(let code, let message):
            return String(localized: "Synology error \(code): \(message)")
        case .transport(let err):
            // System URLError messages localize themselves via the OS;
            // pass through verbatim rather than re-wrapping.
            return err.localizedDescription
        case .serverTrust(let host, _):
            return String(localized: "Couldn't verify the security certificate for \(host).")
        }
    }

    /// `(host, fingerprint)` when this is a `.serverTrust` failure,
    /// else nil. Convenience for the SessionStore / UI to route an
    /// untrusted-certificate error to the trust prompt.
    var serverTrustInfo: (host: String, fingerprint: String)? {
        if case .serverTrust(let host, let fingerprint) = self {
            return (host, fingerprint)
        }
        return nil
    }

    /// Produce a human-readable description of a `DecodingError` that includes the
    /// JSON key path. Critical for diagnosing API surprises — the default
    /// localizedDescription strips the path and just says "data couldn't be read".
    private static func describe(decodingError error: Error) -> String {
        guard let de = error as? DecodingError else { return error.localizedDescription }
        func path(_ context: DecodingError.Context) -> String {
            let segments = context.codingPath.map { key -> String in
                if let i = key.intValue { return "[\(i)]" }
                return key.stringValue
            }
            return segments.isEmpty ? "<root>" : segments.joined(separator: ".")
        }
        switch de {
        case .keyNotFound(let key, let ctx):
            return String(localized: "missing key '\(key.stringValue)' at \(path(ctx))")
        case .valueNotFound(let type, let ctx):
            return String(localized: "missing \(String(describing: type)) value at \(path(ctx))")
        case .typeMismatch(let type, let ctx):
            return String(localized: "wrong type — expected \(String(describing: type)) at \(path(ctx))")
        case .dataCorrupted(let ctx):
            return String(localized: "data corrupted at \(path(ctx)): \(ctx.debugDescription)")
        @unknown default:
            return de.localizedDescription
        }
    }

    /// True when the server told us the SID is no longer valid and we should re-authenticate.
    /// Codes: 105 (no permission), 106 (timeout), 107 (interrupted by duplicate login),
    /// 119 (sid not found — seen on some DSM builds).
    var isSessionExpired: Bool {
        if case .synology(let code, _) = self {
            return code == 105 || code == 106 || code == 107 || code == 119
        }
        return false
    }

    /// True specifically for "session does not have permission" (105). This
    /// is the signature failure of using a SID scoped to the wrong DSM
    /// session name (e.g. plain DSM web session against Download Station
    /// APIs) — distinct from a generally expired session. The recovery
    /// path is a session upgrade via cookies rather than a full re-login.
    var isUnauthorized: Bool {
        if case .synology(let code, _) = self {
            return code == 105
        }
        return false
    }

    /// True for errors that the next refresh tick is likely to recover from on its
    /// own — connectivity glitches, timeouts during a Wi-Fi/cellular handoff,
    /// transient server-side 5xx, etc. Callers should not surface these as alerts;
    /// let the auto-refresh retry.
    var isTransient: Bool {
        switch self {
        case .transport(let err):
            let urlError = err as? URLError
            switch urlError?.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .timedOut, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .secureConnectionFailed,
                 .internationalRoamingOff, .dataNotAllowed:
                return true
            default:
                return urlError != nil
            }
        case .http(let code):
            return code >= 500
        default:
            return false
        }
    }

    /// 403 in the auth context means "2-step verification code required". For accounts
    /// with Synology Secure SignIn enabled the server also sends a push notification
    /// to the user's authenticator app; subsequent login attempts (without an OTP)
    /// will succeed once the user approves there.
    var isOTPRequired: Bool {
        if case .synology(let code, _) = self {
            return code == 403
        }
        return false
    }

    /// 404 in the auth context means "Failed to authenticate 2-step verification code"
    /// — i.e. the OTP we sent was wrong.
    var isOTPInvalid: Bool {
        if case .synology(let code, _) = self {
            return code == 404
        }
        return false
    }
}

// Synology API error codes. Codes in the 4xx range mean different things depending
// on which API returned them (auth vs Download Station task), so the lookup is
// context-aware. See `Synology_Download_Station_Web_API.pdf` for the full list.
enum SynologyErrorCode {
    enum Context {
        case auth
        case task
    }

    static func message(for code: Int, context: Context = .auth) -> String {
        if let common = commonMessage(for: code) {
            return common
        }
        switch context {
        case .auth: return authMessage(for: code)
        case .task: return taskMessage(for: code)
        }
    }

    /// Codes 100-107 are returned by every endpoint with the same meaning.
    private static func commonMessage(for code: Int) -> String? {
        switch code {
        case 100: return String(localized: "Unknown error.")
        case 101: return String(localized: "Invalid parameter.")
        case 102: return String(localized: "The requested API does not exist.")
        case 103: return String(localized: "The requested method does not exist.")
        case 104: return String(localized: "The requested version does not support the functionality.")
        case 105: return String(localized: "The logged in session does not have permission.")
        case 106: return String(localized: "Session timeout.")
        case 107: return String(localized: "Session interrupted by duplicate login.")
        default:  return nil
        }
    }

    private static func authMessage(for code: Int) -> String {
        switch code {
        case 400: return String(localized: "No such account or incorrect password.")
        case 401: return String(localized: "Account disabled.")
        case 402: return String(localized: "Permission denied.")
        case 403: return String(localized: "2-step verification code required.")
        case 404: return String(localized: "Failed to authenticate 2-step verification code.")
        default:  return String(localized: "Synology API returned error \(code).")
        }
    }

    private static func taskMessage(for code: Int) -> String {
        switch code {
        case 400: return String(localized: "File upload failed.")
        case 401: return String(localized: "Maximum number of tasks reached.")
        case 402: return String(localized: "Destination denied.")
        case 403: return String(localized: "Destination does not exist.")
        case 404: return String(localized: "Invalid task ID.")
        case 405: return String(localized: "Invalid task action.")
        case 406: return String(localized: "No default destination configured.")
        case 407: return String(localized: "Set destination failed.")
        case 408: return String(localized: "File does not exist.")
        default:  return String(localized: "Synology API returned error \(code).")
        }
    }
}
