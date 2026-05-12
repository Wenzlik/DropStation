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
        /// In this state the LoginView shows an "approve in your authenticator app, or
        /// enter the code" UI while we silently poll the login endpoint for push approval.
        case twoFactorRequired
        case loggedIn
        case error(String)
    }

    @Published private(set) var state: State = .restoring
    @Published private(set) var config: ServerConfig = ServerConfigStore.load() ?? .default
    @Published var pendingMagnetLink: String?

    let client = SynologyAPIClient()

    /// Credentials captured during the first login attempt, kept in memory only for the
    /// duration of a 2FA challenge so the polling task can re-submit without prompting
    /// the user again.
    private var pendingCredentials: PendingCredentials?
    private var pushPollingTask: Task<Void, Never>?

    private struct PendingCredentials {
        let config: ServerConfig
        let password: String
        let trustThisDevice: Bool
    }

    init() {
        Task { await restoreSession() }
    }

    /// True when a device id is saved for the current account+host. The UI can hide the OTP
    /// field because the next login will skip 2FA.
    var hasTrustedDevice: Bool {
        guard !config.account.isEmpty, !config.host.isEmpty else { return false }
        return KeychainStorage.deviceID(for: accountAtHost) != nil
    }

    // MARK: - Restore

    /// Try to restore a session on app launch:
    ///   1. If we have a saved SID, configure the client and probe the API.
    ///      A successful probe -> we are logged in, nothing else to do.
    ///   2. If the probe fails because the session expired, try a silent re-login using
    ///      the saved password (+ device id, if any).
    ///   3. If we have no SID and no saved credentials, show the login form.
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

        // Try silent re-login using stored password (+ device id if 2FA-trusted).
        if let savedPassword = KeychainStorage.password(for: config.account) {
            do {
                try await performLogin(
                    password: savedPassword,
                    otpCode: nil,
                    deviceID: KeychainStorage.deviceID(for: accountAtHost),
                    enableDeviceToken: false
                )
                return
            } catch {
                // Credentials might have changed server-side, or the device_id was revoked.
                // Fall through to the login form so the user can fix it.
            }
        }

        state = .loggedOut
    }

    // MARK: - Login

    /// Initial login from the form. If the server demands a second factor, we transition
    /// into `.twoFactorRequired` and start polling — the user can wait for the
    /// Synology Secure SignIn push approval or type the OTP into the challenge view.
    func login(config: ServerConfig, password: String, trustThisDevice: Bool = true) async {
        self.config = config
        guard let url = config.baseURL else {
            state = .error("Invalid server URL.")
            return
        }
        await client.configure(baseURL: url)
        state = .authenticating
        await attemptLogin(
            password: password,
            otpCode: nil,
            trustThisDevice: trustThisDevice,
            onOTPNeeded: { [weak self] in
                guard let self else { return }
                self.pendingCredentials = PendingCredentials(
                    config: config, password: password, trustThisDevice: trustThisDevice
                )
                self.state = .twoFactorRequired
                self.startPushPolling()
            }
        )
    }

    /// Submit an OTP code from the 2FA challenge view. Cancels the push polling.
    func submitOTP(_ otpCode: String) async {
        stopPushPolling()
        guard let pending = pendingCredentials else {
            state = .error("Session lost. Please sign in again.")
            return
        }
        state = .authenticating
        await attemptLogin(
            password: pending.password,
            otpCode: otpCode,
            trustThisDevice: pending.trustThisDevice,
            onOTPNeeded: { [weak self] in
                // Server rejected the OTP and is still demanding one.
                self?.state = .twoFactorRequired
                self?.startPushPolling()
            }
        )
    }

    /// Bail out of the 2FA challenge — go back to the credentials form.
    func cancelTwoFactor() {
        stopPushPolling()
        pendingCredentials = nil
        state = .loggedOut
    }

    /// Re-trigger a Synology Secure SignIn push by re-issuing the login attempt now,
    /// in addition to the periodic polling.
    func resendPushApproval() async {
        guard let pending = pendingCredentials else { return }
        await attemptLogin(
            password: pending.password,
            otpCode: nil,
            trustThisDevice: pending.trustThisDevice,
            onOTPNeeded: { /* stay in .twoFactorRequired; already there */ }
        )
    }

    private func attemptLogin(
        password: String,
        otpCode: String?,
        trustThisDevice: Bool,
        onOTPNeeded: @escaping () -> Void
    ) async {
        do {
            try await performLogin(
                password: password,
                otpCode: otpCode,
                deviceID: KeychainStorage.deviceID(for: accountAtHost),
                enableDeviceToken: trustThisDevice
            )
            try? KeychainStorage.setPassword(password, for: config.account)
            ServerConfigStore.save(config)
            pendingCredentials = nil
            stopPushPolling()
        } catch let error as APIError where error.isOTPRequired {
            onOTPNeeded()
        } catch let error as APIError where error.isOTPInvalid {
            state = .error("Incorrect verification code.")
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Shared login path used both by interactive login and silent re-login.
    private func performLogin(
        password: String,
        otpCode: String?,
        deviceID: String?,
        enableDeviceToken: Bool
    ) async throws {
        let result = try await client.login(
            account: config.account,
            password: password,
            otpCode: otpCode,
            enableDeviceToken: enableDeviceToken,
            deviceID: deviceID,
            deviceName: Self.deviceName
        )
        try? KeychainStorage.setSID(result.sid, for: accountAtHost)
        if let did = result.deviceID {
            try? KeychainStorage.setDeviceID(did, for: accountAtHost)
        }
        state = .loggedIn
    }

    // MARK: - Push polling

    /// While `.twoFactorRequired`, retry the login every few seconds. Synology Secure
    /// SignIn pushes an approval prompt to the user's authenticator app; once they tap
    /// "Approve", the next login call (without an OTP) starts returning a valid SID.
    private func startPushPolling() {
        stopPushPolling()
        guard let pending = pendingCredentials else { return }
        pushPollingTask = Task { [weak self] in
            let started = Date()
            // Keep trying for ~2 minutes — about the lifetime of a Synology push prompt.
            while !Task.isCancelled, Date().timeIntervalSince(started) < 120 {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                guard let self else { return }
                await self.pollOnce(pending: pending)
                if await self.state != .twoFactorRequired { return }
            }
        }
    }

    private func stopPushPolling() {
        pushPollingTask?.cancel()
        pushPollingTask = nil
    }

    private func pollOnce(pending: PendingCredentials) async {
        do {
            try await performLogin(
                password: pending.password,
                otpCode: nil,
                deviceID: KeychainStorage.deviceID(for: accountAtHost),
                enableDeviceToken: pending.trustThisDevice
            )
            try? KeychainStorage.setPassword(pending.password, for: config.account)
            ServerConfigStore.save(config)
            pendingCredentials = nil
            stopPushPolling()
        } catch let error as APIError where error.isOTPRequired {
            // Still waiting for the user to approve. Stay in .twoFactorRequired and try again.
        } catch {
            // Anything else (network blip, wrong creds suddenly, etc.) — silently keep polling;
            // the user can still type an OTP or Cancel. We don't move to .error mid-prompt
            // because that would dismiss their 2FA view.
        }
    }

    // MARK: - Logout

    func logout() async {
        stopPushPolling()
        try? await client.logout()
        KeychainStorage.deleteSID(for: accountAtHost)
        // We keep the password and device id so the user can come back without re-entering
        // 2FA. They are cleared by `forgetDevice()`.
        state = .loggedOut
    }

    func forgetDevice() async {
        stopPushPolling()
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

    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "SynoGet iOS"
        #endif
    }
}
