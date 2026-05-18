import Foundation
import SwiftUI
@preconcurrency import WebKit

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
        /// We were logged in, but Download Station rejected the session
        /// with "no permission" (Synology error 105) or a related code.
        /// Distinguishes a recoverable permission loss from a generic
        /// `.error` — the LoginView shows a dedicated recovery card
        /// with re-authenticate / use OTP / sign out actions.
        case sessionUnauthorized(reason: String)
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
        //
        // If we also have Secure SignIn web cookies on file, rehydrate
        // them into HTTPCookieStorage.shared *before* probing the API.
        // Some DSM endpoints (the DS2 entry.cgi flow) honour the cookie
        // in addition to the `_sid` URL parameter, and the cookies are
        // what the web sign-in actually produced — without them an
        // expired SID lookup would be more aggressive than necessary.
        if let savedSID = KeychainStorage.sid(for: accountAtHost) {
            restoreCookiesFromKeychain()
            await client.restoreSession(sid: savedSID)
            do {
                _ = try await client.listTasks()
                state = .loggedIn
                return
            } catch {
                // Failed for any reason — expired SID, transient network
                // hiccup, server unreachable. Drop the SID and cookies,
                // fall through to silent re-login. We don't tell the
                // user yet; the form they're about to see is feedback
                // enough.
                KeychainStorage.deleteSID(for: accountAtHost)
                KeychainStorage.deleteCookies(for: accountAtHost)
                await client.clearSession()
                await client.clearAuthCookies()
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

    /// Soft logout — invalidates the active session on every layer
    /// we know about, but keeps the saved password so the user can
    /// sign in again without retyping. Touches:
    ///   - DSM server-side SID (best-effort, ignore failures)
    ///   - Keychain SID + Secure SignIn cookies
    ///   - HTTPCookieStorage.shared (URLSession layer)
    ///   - WKWebsiteDataStore (anything the web-sign-in WKWebView left
    ///     behind in its non-persistent jar will already be gone, but
    ///     the default store may still have something from a prior
    ///     in-app browser run — wipe it for good measure)
    func logout() async {
        try? await client.logout()
        await client.clearAuthCookies()
        KeychainStorage.deleteSID(for: accountAtHost)
        KeychainStorage.deleteCookies(for: accountAtHost)
        await clearWebsiteData()
        state = .loggedOut
    }

    /// Same as logout, plus wipes the saved password — "remove every
    /// trace of this NAS from the device".
    func forgetDevice() async {
        try? await client.logout()
        await client.clearAuthCookies()
        KeychainStorage.deleteSID(for: accountAtHost)
        KeychainStorage.deleteCookies(for: accountAtHost)
        KeychainStorage.deletePassword(for: config.account)
        await clearWebsiteData()
        state = .loggedOut
    }

    /// Wipe cookies + local storage owned by `WKWebsiteDataStore.default()`.
    /// The Secure SignIn web sheet uses `.nonPersistent()` so its own
    /// jar dies with the sheet, but DSM may have set cookies in the
    /// default store at any earlier point (e.g. if a future revision
    /// opens DSM pages outside the sign-in sheet). Catching everything
    /// here keeps logout semantically honest.
    private func clearWebsiteData() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await store.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    /// Finish a Secure SignIn web login.
    ///
    /// The `id` cookie SID returned by the WKWebView is DSM-wide — not
    /// scoped to Download Station. Using it against
    /// `SYNO.DownloadStation.*` endpoints triggers Synology error 105
    /// ("session does not have permission"). To bridge this we POST
    /// `SYNO.API.Auth.Login` with `session=DownloadStation` *and no
    /// credentials*; DSM authenticates that call via the cookies
    /// URLSession just inherited from the web view, and returns a
    /// fresh SID scoped to Download Station.
    ///
    /// We then validate the upgraded session with a cheap `listTasks`
    /// probe before declaring `.loggedIn`. If anything along the way
    /// goes sideways we surface `.sessionUnauthorized` with a recovery
    /// menu instead of leaving the user staring at a perpetually
    /// 105-erroring task list.
    func completeWebSignIn(
        config: ServerConfig,
        sid: String,
        cookies: [HTTPCookie]
    ) async {
        self.config = config
        guard let url = config.baseURL else {
            state = .error("Invalid server URL.")
            return
        }
        DSLog.session("completeWebSignIn host=\(config.host) initialSid=\(redact(sid)) cookies=\(cookies.count)")
        for c in cookies {
            DSLog.session("  cookie name=\(c.name) domain=\(c.domain) path=\(c.path) secure=\(c.isSecure)")
        }

        await client.configure(baseURL: url)
        // Push the WKWebView's cookies into the shared jar so URLSession
        // requests can send them alongside any `_sid` parameter.
        let storage = HTTPCookieStorage.shared
        for cookie in cookies {
            storage.setCookie(cookie)
        }

        // Diagnostic: log which APIs DSM exposes. Best-effort — if
        // query.cgi itself is broken or unreachable we don't want to
        // block the sign-in over that.
        if let info = try? await client.apiInfo() {
            for (api, entry) in info {
                DSLog.auth("apiInfo \(api) path=\(entry.path) versions=\(entry.minVersion)..\(entry.maxVersion)")
            }
        } else {
            DSLog.auth("apiInfo unavailable (continuing without it)")
        }

        // Try to upgrade the cookie-auth'd DSM session into a real
        // DownloadStation-scoped SID. If this works, replace the SID
        // we picked off the `id` cookie with the new one.
        var effectiveSID = sid
        do {
            let upgraded = try await client.loginUsingCookies(sessionName: "DownloadStation")
            effectiveSID = upgraded.sid
            DSLog.session("session upgrade succeeded: ds sid=\(redact(upgraded.sid))")
        } catch {
            // Upgrade failed — fall back to the raw cookie SID and
            // let the listTasks probe determine if we're stuck. Some
            // DSM builds may not require the upgrade.
            DSLog.session("session upgrade failed: \(error.localizedDescription) — falling back to cookie SID")
            await client.restoreSession(sid: sid)
        }
        await client.restoreSession(sid: effectiveSID)

        // Validate: list tasks. On 105 we're authenticated DSM-wide
        // but not for Download Station; surface a dedicated recovery
        // state rather than a generic .error so the user sees actionable
        // options.
        do {
            _ = try await client.listTasks()
        } catch let error as APIError where error.isUnauthorized {
            DSLog.session("post-upgrade probe got \(error.localizedDescription) — surfacing recovery UI")
            pendingCredentials = nil
            state = .sessionUnauthorized(reason: "Web sign-in succeeded but Download Station rejected the session (\(error.localizedDescription)).")
            return
        } catch {
            DSLog.session("post-upgrade probe failed (\(error.localizedDescription)) — proceeding anyway, refresh will retry")
            // Other errors are likely transient — let auto-refresh
            // handle them in the task list.
        }

        try? KeychainStorage.setSID(effectiveSID, for: accountAtHost)
        // Persist the cookies too so the next launch can rehydrate the
        // jar before probing the API.
        let stored = cookies.map(StoredCookie.init(cookie:))
        try? KeychainStorage.setCookies(stored, for: accountAtHost)
        ServerConfigStore.save(config)
        pendingCredentials = nil
        state = .loggedIn
        DSLog.session("completeWebSignIn → loggedIn (effectiveSid=\(redact(effectiveSID)))")
    }

    /// Called by `TaskListViewModel` when an API call comes back with
    /// "session does not have permission" or related auth-loss codes
    /// after we believed we were logged in. Drops the current session
    /// state and surfaces the recovery card with three options:
    /// re-authenticate, switch to OTP, or full sign out.
    func handleUnauthorized(reason: String) {
        DSLog.session("handleUnauthorized: \(reason)")
        state = .sessionUnauthorized(reason: reason)
    }

    /// Recovery action — switch the auth method preference back to OTP
    /// and drop the session so the user lands on the standard login
    /// form. Useful when the Secure SignIn web flow consistently fails
    /// the DownloadStation upgrade for this NAS.
    func switchToOTPAndSignOut() async {
        UserDefaults.standard.set(AuthMethod.otp.rawValue, forKey: AuthMethodSettings.storageKey)
        await logout()
    }

    /// Hydrate `HTTPCookieStorage.shared` from any cookies we previously
    /// persisted for this account+host. Filters out anything past its
    /// expiry — DSM session cookies routinely have multi-week
    /// lifetimes, but the user might also be coming back to a launch
    /// that already lapsed. No-op when nothing is stored.
    private func restoreCookiesFromKeychain() {
        guard let stored = KeychainStorage.cookies(for: accountAtHost),
              !stored.isEmpty else { return }
        let now = Date()
        let storage = HTTPCookieStorage.shared
        for cookie in stored {
            if let expires = cookie.expiresDate, expires < now { continue }
            if let http = cookie.makeHTTPCookie() {
                storage.setCookie(http)
            }
        }
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
