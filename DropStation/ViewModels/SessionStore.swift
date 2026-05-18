import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case restoring
        case loggedOut
        case authenticating
        /// First-stage credentials accepted; server is waiting for a 6-digit
        /// verification code from an authenticator app (Synology Secure SignIn
        /// Codes tab, Google Authenticator, 1Password, etc.).
        case twoFactorRequired
        case loggedIn
        case error(String)
    }

    @Published private(set) var state: State = .restoring
    @Published private(set) var config: ServerConfig = ServerConfigStore.load() ?? .default
    @Published var pendingMagnetLink: String?

    let client = SynologyAPIClient()

    /// Credentials captured during the first login attempt, kept in memory only for the
    /// duration of a 2FA challenge so submitOTP can re-issue the request without
    /// prompting the user for them again.
    private var pendingCredentials: PendingCredentials?

    private struct PendingCredentials {
        let config: ServerConfig
        let password: String
    }

    /// Guard against running the launch-time session-restore twice. SwiftUI's
    /// `.task` modifier can fire again if the host view is re-attached (e.g.
    /// scenePhase transitions on some iOS builds), and we don't want to clobber
    /// the user's logged-in or login-form state with a second `.restoring`
    /// pass.
    private var didRestoreOnLaunch = false

    // MARK: - Restore

    /// Entry point for app-launch session restore. Wired from `DropStationApp`'s
    /// `WindowGroup` via `.task { await session.restoreOnLaunch() }` instead of
    /// being fired from `init()` — that earlier pattern forced a detached
    /// `Task { ... }` because SwiftUI requires `@StateObject` inits to be
    /// synchronous, which is less structured and harder to cancel/observe.
    /// Idempotent on repeat calls.
    func restoreOnLaunch() async {
        guard !didRestoreOnLaunch else { return }
        didRestoreOnLaunch = true
        await restoreSession()
    }

    /// Try to restore a session on app launch:
    ///   1. If we have a saved SID, probe the API. Success → already logged in.
    ///   2. Otherwise (SID missing, expired, or any other probe failure),
    ///      try a silent re-login using the saved password via
    ///      `silentReLogin`, which handles the 2FA-required branch.
    ///   3. No credentials → land on the login form quietly.
    ///
    /// We don't ever surface an `.error` from this path: launch-time
    /// housekeeping shouldn't pop a "session expired" alert at the user
    /// the moment they open the app — they just want to sign in.
    private func restoreSession() async {
        guard !config.host.isEmpty, !config.account.isEmpty,
              let url = config.baseURL else {
            state = .loggedOut
            return
        }
        await client.configure(baseURL: url)

        // Step 1: Try the saved SID.
        if let savedSID = KeychainStorage.sid(for: accountAtHost) {
            await client.restoreSession(sid: savedSID)
            do {
                _ = try await client.listTasks()
                state = .loggedIn
                return
            } catch {
                // Failed for any reason — expired SID, transient network
                // hiccup, server unreachable. Drop the SID and fall
                // through to silent re-login. We don't tell the user yet;
                // the form they're about to see is feedback enough.
                KeychainStorage.deleteSID(for: accountAtHost)
                await client.clearSession()
            }
        }

        // Step 2: Try silent re-login with stored password.
        if let savedPassword = KeychainStorage.password(for: config.account) {
            await silentReLogin(password: savedPassword)
            return
        }

        state = .loggedOut
    }

    /// Silent re-login with a known password. Drives the same flow as the
    /// initial form-driven sign-in but without UI prompts:
    ///   - success → `.loggedIn` (via `performLogin`)
    ///   - 403 (2FA required) → `.twoFactorRequired`
    ///   - any other error → `.loggedOut`, no alert
    ///
    /// Shared by `restoreSession` (step 2) and `reauthenticate` so both
    /// paths handle 2FA consistently.
    private func silentReLogin(password: String) async {
        pendingCredentials = PendingCredentials(config: config, password: password)
        do {
            try await performLogin(password: password, otpCode: nil)
            ServerConfigStore.save(config)
            pendingCredentials = nil
        } catch let error as APIError where error.isOTPRequired {
            state = .twoFactorRequired
        } catch {
            pendingCredentials = nil
            state = .loggedOut
        }
    }

    // MARK: - Login

    /// Initial login from the form. If the server demands a second factor,
    /// transition to `.twoFactorRequired` and wait for the user to type a code.
    func login(config: ServerConfig, password: String) async {
        self.config = config
        guard let url = config.baseURL else {
            state = .error("Invalid server URL.")
            return
        }
        await client.configure(baseURL: url)
        // Wipe any DSM trusted-device cookies left over from previous
        // logins. Without this, DSM may silently honour a stale `did`
        // cookie and skip the 2FA challenge entirely. Every form-driven
        // sign-in should be a fresh, fully-challenged login.
        await client.clearAuthCookies()
        state = .authenticating
        pendingCredentials = PendingCredentials(config: config, password: password)
        await attemptLogin(
            password: password,
            otpCode: nil,
            onOTPNeeded: { [weak self] in
                self?.state = .twoFactorRequired
            }
        )
    }

    /// Submit an OTP code from the 2FA challenge view.
    func submitOTP(_ otpCode: String) async {
        guard let pending = pendingCredentials else {
            state = .error("Session lost. Please sign in again.")
            return
        }
        state = .authenticating
        await attemptLogin(
            password: pending.password,
            otpCode: otpCode,
            onOTPNeeded: { [weak self] in
                self?.state = .twoFactorRequired
            }
        )
    }

    /// Bail out of the 2FA challenge — go back to the credentials form.
    func cancelTwoFactor() {
        pendingCredentials = nil
        state = .loggedOut
    }

    private func attemptLogin(
        password: String,
        otpCode: String?,
        onOTPNeeded: @escaping () -> Void
    ) async {
        do {
            try await performLogin(password: password, otpCode: otpCode)
            try? KeychainStorage.setPassword(password, for: config.account)
            ServerConfigStore.save(config)
            pendingCredentials = nil
        } catch let error as APIError where error.isOTPRequired {
            onOTPNeeded()
        } catch let error as APIError where error.isOTPInvalid {
            state = .error("Incorrect verification code.")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// The single Synology `login` call. Sends just account/password/otpCode —
    /// no device-token plumbing. SID is the only thing we persist; when it
    /// expires, the next launch surfaces the password+2FA prompt again.
    private func performLogin(password: String, otpCode: String?) async throws {
        let result = try await client.login(
            account: config.account,
            password: password,
            otpCode: otpCode
        )
        try? KeychainStorage.setSID(result.sid, for: accountAtHost)
        state = .loggedIn
    }

    // MARK: - Logout

    func logout() async {
        try? await client.logout()
        KeychainStorage.deleteSID(for: accountAtHost)
        state = .loggedOut
    }

    func forgetDevice() async {
        try? await client.logout()
        await client.clearAuthCookies()
        KeychainStorage.deleteSID(for: accountAtHost)
        KeychainStorage.deletePassword(for: config.account)
        state = .loggedOut
    }

    /// Force a fresh 2FA challenge without making the user retype their
    /// password. Invalidates the local + server-side session and wipes
    /// DSM's trusted-device cookies, then silently re-logs in with the
    /// saved password — which will hit a real 2FA prompt because the
    /// trust is gone. Surfaced in Settings as "Re-authenticate now".
    ///
    /// Falls back to a normal logout if no password is on file (we can't
    /// re-login silently without it).
    func reauthenticate() async {
        guard !config.host.isEmpty, !config.account.isEmpty,
              let url = config.baseURL,
              let savedPassword = KeychainStorage.password(for: config.account)
        else {
            await logout()
            return
        }
        await client.configure(baseURL: url)
        try? await client.logout()
        KeychainStorage.deleteSID(for: accountAtHost)
        await client.clearAuthCookies()
        state = .restoring
        await silentReLogin(password: savedPassword)
    }

    /// Handle magnet: links opened from outside the app.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "magnet" else { return }
        pendingMagnetLink = url.absoluteString
    }

    // MARK: - Helpers

    private var accountAtHost: String { "\(config.account)@\(config.host)" }
}
