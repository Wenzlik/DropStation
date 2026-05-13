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
    ///   2. If the SID expired, try a silent re-login using the saved password.
    ///      The server will trigger 2FA again (push approval or OTP) — we surface
    ///      the 2FA prompt so the user can complete it.
    ///   3. If we have no SID and no saved password, show the login form.
    private func restoreSession() async {
        guard !config.host.isEmpty, !config.account.isEmpty,
              let url = config.baseURL else {
            state = .loggedOut
            return
        }
        await client.configure(baseURL: url)

        if let savedSID = KeychainStorage.sid(for: accountAtHost) {
            await client.restoreSession(sid: savedSID)
            do {
                _ = try await client.listTasks()
                state = .loggedIn
                return
            } catch let error as APIError where error.isSessionExpired {
                // Expected: SID expired. Drop it and fall through to silent re-login.
                KeychainStorage.deleteSID(for: accountAtHost)
                await client.clearSession()
            } catch {
                // Any other error (network, server down) — keep the saved SID, surface the form
                // so the user can retry. We don't drop the SID; it may still be valid later.
                state = .error(error.localizedDescription)
                return
            }
        }

        // Try silent re-login using stored password.
        if let savedPassword = KeychainStorage.password(for: config.account) {
            self.pendingCredentials = PendingCredentials(config: config, password: savedPassword)
            await attemptLogin(
                password: savedPassword,
                otpCode: nil,
                onOTPNeeded: { [weak self] in
                    self?.state = .twoFactorRequired
                }
            )
            return
        }

        state = .loggedOut
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
        KeychainStorage.deleteSID(for: accountAtHost)
        KeychainStorage.deletePassword(for: config.account)
        state = .loggedOut
    }

    /// Handle magnet: links opened from outside the app.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "magnet" else { return }
        pendingMagnetLink = url.absoluteString
    }

    // MARK: - Helpers

    private var accountAtHost: String { "\(config.account)@\(config.host)" }
}
