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
    ///   1. If we have a saved SID, probe Download Station with it.
    ///      Success → already logged in, no OTP prompt.
    ///   2. SID rejected by DSM (105/106/107/119) → drop SID +
    ///      metadata + cookies, land on the login screen so the user
    ///      can re-authenticate. We **do not** silently retry with a
    ///      stored password — password persistence is gated behind a
    ///      separate opt-in we haven't shipped yet.
    ///   3. Transient failure (offline, DNS, 5xx) → keep the SID
    ///      untouched so the next launch can try again, but land on
    ///      the login screen for this launch.
    ///   4. No saved SID → quiet `.loggedOut`.
    ///
    /// We don't ever surface an `.error` from this path: launch-time
    /// housekeeping shouldn't pop a "session expired" alert at the user
    /// the moment they open the app — they just want to sign in.
    private func restoreSession() async {
        // One-shot migration: clear any password an earlier build left
        // in the Keychain. 0.4.0 stops persisting passwords entirely,
        // and we don't want a stale credential lingering on disk on
        // users who upgraded.
        purgeLegacyPasswordIfPresent()

        guard !config.host.isEmpty, !config.account.isEmpty,
              let url = config.baseURL else {
            state = .loggedOut
            return
        }
        await client.configure(baseURL: url)

        // If we also have Secure SignIn web cookies on file, rehydrate
        // them into HTTPCookieStorage.shared *before* probing the API.
        // Some DSM endpoints (the DS2 entry.cgi flow) honour the cookie
        // in addition to the `_sid` URL parameter, and the cookies are
        // what the web sign-in actually produced — without them an
        // expired SID lookup would be more aggressive than necessary.
        guard let savedSID = KeychainStorage.sid(for: accountAtHost) else {
            state = .loggedOut
            return
        }
        restoreCookiesFromKeychain()
        await client.restoreSession(sid: savedSID)
        do {
            _ = try await client.listTasks()
            touchSessionMetadata()
            state = .loggedIn
        } catch let error as APIError where error.isSessionExpired {
            // DSM actively rejected the SID — wipe it so the next
            // launch doesn't keep retrying a dead session, and land
            // on the login screen so the user can sign in fresh.
            DSLog.session("restoreSession: SID rejected (\(error.localizedDescription)); dropping")
            await clearStoredSession()
            state = .loggedOut
        } catch let error as APIError where error.isTransient {
            // Offline / Wi-Fi handoff / server 5xx. Don't punish the
            // user by deleting a SID that's probably still good —
            // they'll get a normal sign-in form for this launch and
            // we'll try again next time.
            DSLog.session("restoreSession: transient (\(error.localizedDescription)); keeping SID")
            state = .loggedOut
        } catch {
            // Anything else (decoding, unexpected HTTP code). Treat
            // like transient: don't drop the SID, just show the
            // login screen.
            DSLog.session("restoreSession: unexpected probe error (\(error.localizedDescription)); keeping SID")
            state = .loggedOut
        }
    }

    /// Best-effort delete of a password an earlier build may have left
    /// in the Keychain. 0.4.0 dropped password persistence; this
    /// migration keeps users who upgrade from <0.4.0 from carrying a
    /// stale credential indefinitely. Runs on every launch (it's
    /// idempotent and cheap when there's nothing to remove).
    private func purgeLegacyPasswordIfPresent() {
        guard !config.account.isEmpty else { return }
        if KeychainStorage.password(for: config.account) != nil {
            DSLog.session("purging legacy stored password from Keychain")
            KeychainStorage.deletePassword(for: config.account)
        }
    }

    /// Drop every persisted credential we hold for the current
    /// account+host, plus the in-memory SID on the API client. Used by
    /// every path that needs to invalidate a session: a rejected SID
    /// probe, an unauthorized list refresh, a logout. Idempotent.
    private func clearStoredSession() async {
        clearStoredKeychainSession()
        await client.clearSession()
        await client.clearAuthCookies()
    }

    /// Keychain-only teardown for callers that can't await (sync
    /// MainActor hooks). The caller is responsible for tearing the
    /// in-memory SID / cookies down separately via a `Task`.
    private func clearStoredKeychainSession() {
        KeychainStorage.deleteSID(for: accountAtHost)
        KeychainStorage.deleteCookies(for: accountAtHost)
        KeychainStorage.deleteSessionMetadata(for: accountAtHost)
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
            // Server config (host/port/account/scheme) is not a
            // credential — always remember it so the login form
            // prefills. The password is never persisted by
            // "Remember session"; that's reserved for a separate
            // opt-in toggle we haven't added yet.
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
    /// no device-token plumbing. When "Remember session" is on, persists the
    /// returned SID plus a `SessionMetadata` sidecar; otherwise the SID stays
    /// in memory for the duration of the app run only.
    private func performLogin(password: String, otpCode: String?) async throws {
        let result = try await client.login(
            account: config.account,
            password: password,
            otpCode: otpCode
        )
        persistSessionIfAllowed(sid: result.sid, cookies: [])
        state = .loggedIn
    }

    /// Persist the freshly-acquired SID + session metadata (and any
    /// Secure SignIn web cookies) when the user has opted in to
    /// "Remember session". A best-effort write — keychain failures
    /// don't break the active session, they just mean the next launch
    /// will require a fresh sign-in.
    private func persistSessionIfAllowed(sid: String, cookies: [HTTPCookie]) {
        guard RememberSessionSettings.enabled else { return }
        try? KeychainStorage.setSID(sid, for: accountAtHost)
        if !cookies.isEmpty {
            let stored = cookies.map(StoredCookie.init(cookie:))
            try? KeychainStorage.setCookies(stored, for: accountAtHost)
        }
        try? KeychainStorage.setSessionMetadata(makeMetadata(), for: accountAtHost)
    }

    /// Build a fresh `SessionMetadata` snapshot for the current config.
    /// `createdAt` and `lastValidatedAt` are both set to `now` — the
    /// probe path bumps `lastValidatedAt` independently on every
    /// successful API round-trip.
    private func makeMetadata(now: Date = Date()) -> SessionMetadata {
        SessionMetadata(
            baseURL: config.baseURL?.absoluteString ?? "",
            account: config.account,
            sessionName: SessionMetadata.downloadStationSession,
            createdAt: now,
            lastValidatedAt: now
        )
    }

    /// Bump `lastValidatedAt` after a successful API call so the
    /// foreground probe knows the session is fresh. Reads the existing
    /// metadata to preserve `createdAt`; if nothing's on file (remember
    /// turned on mid-session, or first-ever launch after upgrade), we
    /// synthesize a record so the next probe still has something to
    /// throttle against.
    private func touchSessionMetadata() {
        guard RememberSessionSettings.enabled else { return }
        var meta = KeychainStorage.sessionMetadata(for: accountAtHost) ?? makeMetadata()
        meta.lastValidatedAt = Date()
        try? KeychainStorage.setSessionMetadata(meta, for: accountAtHost)
    }

    // MARK: - Logout

    /// Logout — invalidates the active session on every layer we know
    /// about. Touches:
    ///   - DSM server-side SID (best-effort, ignore failures)
    ///   - Keychain SID + Secure SignIn cookies + session metadata
    ///   - Any legacy password an older build may have left behind
    ///     (current builds never persist passwords)
    ///   - HTTPCookieStorage.shared (URLSession layer)
    ///   - WKWebsiteDataStore (anything the web-sign-in WKWebView left
    ///     behind in its non-persistent jar will already be gone, but
    ///     the default store may still have something from a prior
    ///     in-app browser run — wipe it for good measure)
    func logout() async {
        try? await client.logout()
        await clearStoredSession()
        KeychainStorage.deletePassword(for: config.account)
        await clearWebsiteData()
        state = .loggedOut
    }

    /// Same as logout. Kept as a separate entry point because the
    /// Settings UI still surfaces it under a distinct "Forget this
    /// device" affordance with destructive-button styling — the user
    /// expectation differs (full wipe vs. casual sign-out) even though
    /// the underlying cleanup is now identical to `logout`.
    func forgetDevice() async {
        await logout()
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
        ServerConfigStore.save(config)
        persistSessionIfAllowed(sid: sid, cookies: cookies)
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
    /// after we believed we were logged in. Drops the persisted SID +
    /// metadata + cookies (so the next launch doesn't immediately try
    /// the same dead session) and surfaces the recovery card with three
    /// options: re-authenticate, switch to OTP, or full sign out. The
    /// in-memory client state is torn down on a detached task because
    /// the caller is a synchronous hook.
    func handleUnauthorized(reason: String) {
        DSLog.session("handleUnauthorized: \(reason)")
        clearStoredKeychainSession()
        Task {
            await client.clearSession()
            await client.clearAuthCookies()
        }
        state = .sessionUnauthorized(reason: reason)
    }

    // MARK: - Foreground probe

    /// Throttled silent revalidation. Designed to run from
    /// `scenePhase == .active` on every foreground transition: if the
    /// SID hasn't been confirmed alive in the last `throttle` seconds,
    /// fire a cheap `listTasks` request and react to whatever DSM
    /// returns.
    ///
    /// Bails early — and silently — in the common case (nothing to
    /// probe, just-validated session, transient network blip), so the
    /// only user-visible effect is the recovery card popping when the
    /// session is genuinely gone.
    func probeIfStale(throttle: TimeInterval = 600) async {
        guard state == .loggedIn else { return }
        guard let meta = KeychainStorage.sessionMetadata(for: accountAtHost) else { return }
        let elapsed = Date().timeIntervalSince(meta.lastValidatedAt)
        guard elapsed >= throttle else { return }

        DSLog.session("probeIfStale: elapsed=\(Int(elapsed))s, probing")
        do {
            _ = try await client.listTasks()
            touchSessionMetadata()
        } catch let error as APIError where error.isSessionExpired {
            DSLog.session("probeIfStale: session expired — \(error.localizedDescription)")
            await clearStoredSession()
            state = .sessionUnauthorized(reason: "Session expired. Please re-authenticate.")
        } catch let error as APIError where error.isTransient {
            // Offline / handoff / 5xx — leave the session alone, the
            // next probe will retry.
            DSLog.session("probeIfStale: transient (\(error.localizedDescription))")
        } catch {
            // Decoding or unexpected HTTP — also leave the session
            // alone. We'd rather mis-classify than kick the user out
            // for a parser glitch.
            DSLog.session("probeIfStale: ignored (\(error.localizedDescription))")
        }
    }

    // MARK: - Remember-session preference

    /// Settings-toggle entry point. Writes the user pref. Turning the
    /// toggle off clears the persisted SID + metadata + cookies — the
    /// "session" being remembered. The active in-memory session is
    /// left intact so the user can keep using the app for this run
    /// without an immediate re-sign-in.
    ///
    /// Password isn't part of "Remember session" any more (0.4.0
    /// dropped automatic password persistence), but we still call
    /// `deletePassword` here defensively so that flipping the toggle
    /// off on a device upgraded from an older build clears the legacy
    /// credential too.
    func setRememberSession(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: RememberSessionSettings.storageKey)
        DSLog.session("rememberSession = \(enabled)")
        if !enabled {
            clearStoredKeychainSession()
            KeychainStorage.deletePassword(for: config.account)
        }
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

    /// Handle magnet: links opened from outside the app.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "magnet" else { return }
        pendingMagnetLink = url.absoluteString
    }

    // MARK: - Helpers

    private var accountAtHost: String { "\(config.account)@\(config.host)" }
}
