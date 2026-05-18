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
        /// Brief intermediate state after a Secure SignIn web sign-in:
        /// the WKWebView's auth round-trip succeeded, but we haven't yet
        /// confirmed Download Station accepts the resulting session.
        /// Shown as "Secure SignIn verified. Checking Download Station
        /// access…" with a spinner. Either flips to `.loggedIn` or
        /// `.sessionUnauthorized` depending on the probe outcome.
        case validatingApiAccess
        /// Terminal "fully authenticated" state — Download Station API
        /// probe came back success=true. Only this state grants access
        /// to the main task list.
        case loggedIn
        /// Web sign-in succeeded but DSM did not extend that auth to
        /// the Download Station API (Synology error 105). Web identity
        /// is verified; API identity is not. The recovery card offers
        /// "Continue with OTP" and "Retry web login".
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
    /// What the WKWebView round-trip actually buys us: a *web identity*
    /// — DSM's cookies (`id`, `did`, `stay_login`) say "this user is
    /// signed in to DSM web". That is **not** the same thing as having
    /// API access to Download Station. Synology binds API permissions
    /// to a `session=...` parameter passed to `auth.cgi` at login time,
    /// and the web flow's session name is the DSM-wide one, which
    /// `SYNO.DownloadStation.*` endpoints reject with error 105.
    ///
    /// Earlier we tried to "upgrade" the cookie session by re-calling
    /// `auth.cgi&method=login&session=DownloadStation` without
    /// credentials — DSM treats that as a brand-new login attempt and
    /// returns 400 "No such account". So instead we treat web identity
    /// and API identity as separate concerns:
    ///
    ///   1. Install the harvested cookies into the shared jar.
    ///   2. Use the `id` cookie value as a candidate SID.
    ///   3. Run a real Download Station probe (`validateDownloadStationAccess`).
    ///   4. Probe succeeds → persist + transition to `.loggedIn`.
    ///   5. Probe returns 105 → `.sessionUnauthorized` with a recovery
    ///      card directing the user to OTP (or retry).
    ///   6. Probe fails transiently → `.error(...)`, user retries from
    ///      the login form.
    ///
    /// We never call `.loggedIn` before step 4 succeeds, so the task
    /// list never appears with a broken session behind it.
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
        // requests can send them automatically.
        let storage = HTTPCookieStorage.shared
        for cookie in cookies {
            storage.setCookie(cookie)
        }
        await client.restoreSession(sid: sid)

        // Show the user we're working before the probe completes —
        // otherwise the WKWebView sheet just dismisses and they're
        // looking at the login form for a beat with no feedback.
        state = .validatingApiAccess

        // Diagnostic: dump available APIs once per web sign-in. Behind
        // DEBUG only via DSLog. Doesn't gate the probe.
        if let info = try? await client.apiInfo() {
            for (api, entry) in info {
                DSLog.auth("apiInfo \(api) path=\(entry.path) versions=\(entry.minVersion)..\(entry.maxVersion)")
            }
        } else {
            DSLog.auth("apiInfo unavailable")
        }

        do {
            try await validateDownloadStationAccess()
        } catch let error as APIError where error.isUnauthorized {
            DSLog.session("DS probe → 105; web identity verified but no API permission")
            pendingCredentials = nil
            state = .sessionUnauthorized(
                reason: "Secure SignIn login succeeded, but DSM did not grant API access to Download Station."
            )
            return
        } catch {
            DSLog.session("DS probe failed: \(error.localizedDescription)")
            pendingCredentials = nil
            state = .error("Couldn't reach Download Station: \(error.localizedDescription)")
            return
        }

        // Probe passed — now (and only now) we're fully authenticated.
        try? KeychainStorage.setSID(sid, for: accountAtHost)
        let stored = cookies.map(StoredCookie.init(cookie:))
        try? KeychainStorage.setCookies(stored, for: accountAtHost)
        ServerConfigStore.save(config)
        pendingCredentials = nil
        state = .loggedIn
        DSLog.session("completeWebSignIn → loggedIn (sid=\(redact(sid)))")
    }

    /// Run a real Download Station request and require success=true.
    /// Throws on any failure (105, transient, decoding, etc.) so the
    /// caller can branch on `isUnauthorized` / `isTransient` and react
    /// appropriately. Used by `completeWebSignIn` as the gating probe
    /// between web sign-in and `.loggedIn`.
    private func validateDownloadStationAccess() async throws {
        _ = try await client.listTasks()
    }

    /// Recovery action from the `.sessionUnauthorized` card — re-open
    /// the Secure SignIn web flow without changing the user's saved
    /// auth-method preference. Implemented as "drop the half-broken
    /// session and go back to the login form"; the picker already
    /// shows `.secureSignInWeb`, so the next tap on Continue re-opens
    /// the WKWebView sheet.
    func retryWebSignIn() async {
        DSLog.session("retryWebSignIn — clearing session, returning to login form")
        await logout()
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
