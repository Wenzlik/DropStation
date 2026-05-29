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
        case .invalidURL: return "Invalid server URL."
        case .notLoggedIn: return "Not logged in."
        case .http(let code): return "HTTP error \(code)."
        case .decoding(let err): return "Decoding error: \(Self.describe(decodingError: err))"
        case .synology(let code, let message): return "Synology error \(code): \(message)"
        case .transport(let err): return err.localizedDescription
        case .serverTrust(let host, _): return "Couldn't verify the security certificate for \(host)."
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
            return "missing key '\(key.stringValue)' at \(path(ctx))"
        case .valueNotFound(let type, let ctx):
            return "missing \(type) value at \(path(ctx))"
        case .typeMismatch(let type, let ctx):
            return "wrong type — expected \(type) at \(path(ctx))"
        case .dataCorrupted(let ctx):
            return "data corrupted at \(path(ctx)): \(ctx.debugDescription)"
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
        case 100: return "Unknown error."
        case 101: return "Invalid parameter."
        case 102: return "The requested API does not exist."
        case 103: return "The requested method does not exist."
        case 104: return "The requested version does not support the functionality."
        case 105: return "The logged in session does not have permission."
        case 106: return "Session timeout."
        case 107: return "Session interrupted by duplicate login."
        default:  return nil
        }
    }

    private static func authMessage(for code: Int) -> String {
        switch code {
        case 400: return "No such account or incorrect password."
        case 401: return "Account disabled."
        case 402: return "Permission denied."
        case 403: return "2-step verification code required."
        case 404: return "Failed to authenticate 2-step verification code."
        default:  return "Synology API returned error \(code)."
        }
    }

    private static func taskMessage(for code: Int) -> String {
        switch code {
        case 400: return "File upload failed."
        case 401: return "Maximum number of tasks reached."
        case 402: return "Destination denied."
        case 403: return "Destination does not exist."
        case 404: return "Invalid task ID."
        case 405: return "Invalid task action."
        case 406: return "No default destination configured."
        case 407: return "Set destination failed."
        case 408: return "File does not exist."
        default:  return "Synology API returned error \(code)."
        }
    }
}
