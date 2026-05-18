import Foundation

/// Which 2-factor flow the user wants to run.
///
/// DSM exposes two practical paths for second-factor authentication:
///
/// - **OTP** — a 6-digit time-based code entered into the app. Works against
///   `auth.cgi` directly with `otp_code=...`. This is the long-standing
///   default; nothing extra is needed beyond a TOTP app
///   (Synology Secure SignIn Codes tab, Google Authenticator, 1Password, …).
///
/// - **Secure SignIn Web** — DSM's "Approve sign-in" push notification.
///   The flow can't be driven through `auth.cgi` (the push approval
///   doesn't unblock that endpoint), so we open the real DSM web login
///   inside a `WKWebView` and let DSM run its own JavaScript-driven
///   challenge. The user signs in there, taps Approve in the Secure
///   SignIn app, the web view detects the post-login redirect, and we
///   harvest the session cookies for subsequent API calls.
enum AuthMethod: String, CaseIterable, Identifiable, Codable {
    case otp
    case secureSignInWeb

    var id: String { rawValue }

    var label: String {
        switch self {
        case .otp:             return "Verification code"
        case .secureSignInWeb: return "Secure SignIn app"
        }
    }

    /// Sub-label shown next to the picker option to explain when each one
    /// is appropriate. Short — fits under the picker row.
    var subtitle: String {
        switch self {
        case .otp:
            return "Enter a 6-digit code from a TOTP app."
        case .secureSignInWeb:
            return "Approve a push notification in Synology Secure SignIn."
        }
    }

    var systemImage: String {
        switch self {
        case .otp:             return "number.square"
        case .secureSignInWeb: return "iphone.gen3.radiowaves.left.and.right"
        }
    }
}

/// UserDefaults key for the user's last-picked auth method. We restore it
/// on launch so a returning user lands on the same flow they used before
/// instead of always defaulting to OTP.
enum AuthMethodSettings {
    static let storageKey = "auth.method"
}
