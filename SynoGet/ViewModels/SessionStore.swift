import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case restoring
        case loggedOut
        case authenticating
        /// First-stage credentials accepted; server is waiting for 2-step verification.
        ///
        /// Depending on the account settings, "verification" can mean either:
        ///   - tapping Approve on the Synology Secure SignIn push notification
        ///     that arrives on the user's authenticator app, or
        ///   - typing the 6-digit TOTP code into the OTP field.
        /// Either one completes the same `submitOTP` flow (push approval lets the
        /// next login succeed without an OTP code).
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

    init() {
        Task { await restoreSession() }
    }

    // MARK: - Restore

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

    /// Initial login from the form. If the server demands a second factor, transition
    /// to `.twoFactorRequired` and wait — the server has typically also sent a push
    /// to Synology Secure SignIn, so the user can either Approve the push or enter
    /// the 6-digit TOTP code.
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

    /// User has tapped Approve on the Secure SignIn push — retry the login.
    /// (Also available as the "I approved — sign in" button on the 2FA card.)
    func retryAfterPushApproval() async {
        guard let pending = pendingCredentials else { return }
        state = .authenticating
        await attemptLogin(
            password: pending.password,
            otpCode: nil,
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

    /// The single Synology `login` call. Intentionally does NOT pass
    /// `enable_device_token` or `device_id` — those flags switch the server into
    /// a TOTP-only flow and suppress the Secure SignIn push notification, which
    /// is the opposite of what we want. SID is the only thing we persist.
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
        KeychainStorage.deleteDeviceID(for: accountAtHost)
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
