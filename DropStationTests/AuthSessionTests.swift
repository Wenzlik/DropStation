import XCTest
@testable import DropStation

private final class AuthMockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> String)?
    static var responseHeaders: [String: String]?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let body = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: Self.responseHeaders)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}

    static func body(_ request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
final class AuthSessionRequestTests: XCTestCase {
    private let config = ServerConfig(scheme: .https, host: "auth-tests.invalid", port: 5001, account: "native-user")
    private var preferences: [String: Any] = [:]
    private let preferenceKeys = [RememberSessionSettings.storageKey, PasswordPersistenceSettings.storageKey, "synology.server.config"]

    override func setUp() async throws {
        for key in preferenceKeys { preferences[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.set(false, forKey: RememberSessionSettings.storageKey)
        UserDefaults.standard.set(false, forKey: PasswordPersistenceSettings.storageKey)
        ServerConfigStore.clear()
    }

    override func tearDown() async throws {
        for key in preferenceKeys {
            if let value = preferences[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        AuthMockProtocol.handler = nil
        AuthMockProtocol.responseHeaders = nil
    }

    private func client() async -> SynologyAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthMockProtocol.self]
        configuration.httpCookieStorage = nil
        let client = SynologyAPIClient(session: URLSession(configuration: configuration))
        await client.configure(baseURL: config.baseURL!)
        return client
    }

    /// A web session (cookies present) must carry its CSRF token to
    /// every endpoint shape: DS1 form posts, DS2 entry.cgi, FileStation
    /// and the multipart upload.
    func testTokenReachesDS1DS2FileStationAndMultipart() async throws {
        let client = await client()
        let cookie = HTTPCookie(properties: [
            .name: "id", .value: "web-sid",
            .domain: "auth-tests.invalid", .path: "/",
        ])!
        await client.restoreSession(AuthSession(sid: "sid", synoToken: "csrf&+="), cookies: [cookie])
        AuthMockProtocol.handler = { request in
            let body = AuthMockProtocol.body(request)
            if request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart") == true {
                XCTAssertTrue(body.contains("name=\"SynoToken\"\r\n\r\ncsrf&+="))
                XCTAssertTrue(body.contains("name=\"torrent\""))
                XCTAssertTrue(request.url!.query!.contains("_sid=sid"))
            } else { XCTAssertTrue(body.contains("SynoToken=csrf%26%2B%3D")) }
            return #"{"success":true,"data":{"tasks":[],"shares":[]}}"#
        }
        _ = try await client.listTasks()
        try await client.stopTasks(ids: ["task"])
        _ = try await client.listShares()
        try await client.createTask(fileData: Data("torrent".utf8), filename: "test.torrent")
    }

    func testLoginRequestsTokenWithoutLeakingOldTokenAndClearRemovesIt() async throws {
        let client = await client()
        await client.restoreSession(AuthSession(sid: "old", synoToken: "oldToken"))
        AuthMockProtocol.handler = { request in
            let body = AuthMockProtocol.body(request)
            XCTAssertTrue(body.contains("enable_syno_token=yes"))
            XCTAssertFalse(body.contains("SynoToken="))
            return #"{"success":true,"data":{"sid":"new","synotoken":"newToken"}}"#
        }
        let result = try await client.login(account: "user", password: "password")
        XCTAssertEqual(result, AuthSession(sid: "new", synoToken: "newToken"))
        await client.clearSession()
        await client.restoreSession(sid: "legacy")
        AuthMockProtocol.handler = { request in
            XCTAssertFalse(AuthMockProtocol.body(request).contains("SynoToken="))
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        _ = try await client.listTasks()
    }

    /// A native `_sid`-only session must never send `SynoToken`.
    ///
    /// DSM validates the token against the session its *cookie*
    /// identifies. Since the native session sends no cookie, a token
    /// riding along has nothing to pair with, and DSM builds that
    /// enforce the pairing reply 105 — the error that drives the OTP
    /// login loop even though the SID itself is fine.
    func testNativeSessionDoesNotSendCsrfTokenWithoutCookies() async throws {
        let client = await client()
        AuthMockProtocol.handler = { _ in
            #"{"success":true,"data":{"sid":"native-sid","synotoken":"minted"}}"#
        }
        let auth = try await client.login(account: "user", password: "pass", otpCode: "123456")
        XCTAssertEqual(auth.synoToken, "minted", "DSM still mints a token; we just must not use it")

        AuthMockProtocol.handler = { request in
            let body = AuthMockProtocol.body(request)
            XCTAssertFalse(body.contains("SynoToken="),
                           "Cookieless native session must not send SynoToken — DSM answers 105")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            // DS1 form posts carry `_sid` in the body, DS2 entry.cgi in
            // the URL query — either way it must be the only auth channel.
            let query = request.url?.query ?? ""
            XCTAssertTrue(body.contains("_sid=native-sid") || query.contains("_sid=native-sid"))
            return #"{"success":true,"data":{"tasks":[],"shares":[]}}"#
        }
        _ = try await client.listTasks()
        try await client.stopTasks(ids: ["task"])
        _ = try await client.listShares()

        AuthMockProtocol.handler = { request in
            XCTAssertFalse(AuthMockProtocol.body(request).contains("name=\"SynoToken\""),
                           "Multipart upload must not carry SynoToken on a native session")
            return #"{"success":true}"#
        }
        try await client.createTask(fileData: Data("torrent".utf8), filename: "test.torrent")
    }

    private func webCookie(value: String = "web-sid") -> HTTPCookie {
        HTTPCookie(properties: [
            .name: "id", .value: value,
            .domain: "auth-tests.invalid", .path: "/",
        ])!
    }

    func testWebProbeRejects105AndClearsCandidate() async {
        let client = await client()
        let store = SessionStore(client: client)
        AuthMockProtocol.handler = { _ in #"{"success":false,"error":{"code":105}}"# }
        await store.completeWebSignIn(config: config, auth: AuthSession(sid: "web", synoToken: "csrf"), cookies: [webCookie()])
        guard case .sessionUnauthorized = store.state else { return XCTFail("Expected recovery") }
        XCTAssertTrue(store.isWebRecovery)
        XCTAssertFalse(store.canRetryWebValidation)
        let loggedIn = await client.isLoggedIn
        XCTAssertFalse(loggedIn)
        XCTAssertEqual(store.config.account, "")
        let hasCookies = await client.hasWebCookies
        XCTAssertFalse(hasCookies, "Rejected web session must clear cookies from client")
    }

    func testWebTransientFailureRetriesWithoutRepeatingLogin() async {
        let client = await client()
        let store = SessionStore(client: client)
        let cookie = webCookie(value: "retry-sid")
        AuthMockProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await store.completeWebSignIn(config: config, auth: AuthSession(sid: "web", synoToken: "csrf"), cookies: [cookie])
        XCTAssertTrue(store.canRetryWebValidation)
        guard case .sessionUnauthorized = store.state else { return XCTFail("Expected retry") }
        AuthMockProtocol.handler = { request in
            XCTAssertTrue(AuthMockProtocol.body(request).contains("SynoToken=csrf"))
            let cookieHeader = request.value(forHTTPHeaderField: "Cookie")
            XCTAssertTrue(cookieHeader?.contains("retry-sid") == true,
                          "Retry must forward web cookies")
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        await store.retryWebValidation()
        XCTAssertEqual(store.state, .loggedIn)
        XCTAssertFalse(store.canRetryWebValidation)
        await store.logout()
    }

    func testWebSessionColdRestoreWorksWithoutNativeUsername() async throws {
        UserDefaults.standard.set(true, forKey: RememberSessionSettings.storageKey)
        let client = await client()
        let store = SessionStore(client: client)
        let cookie = webCookie(value: "persist-sid")
        AuthMockProtocol.handler = { request in
            let cookieHeader = request.value(forHTTPHeaderField: "Cookie")
            XCTAssertTrue(cookieHeader?.contains("persist-sid") == true,
                          "Initial web probe must forward cookies")
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        await store.completeWebSignIn(config: config, auth: AuthSession(sid: "web", synoToken: "csrf"), cookies: [cookie])
        XCTAssertEqual(store.state, .loggedIn)
        let restored = SessionStore(client: await self.client())
        AuthMockProtocol.handler = { request in
            XCTAssertTrue(AuthMockProtocol.body(request).contains("SynoToken=csrf"))
            let cookieHeader = request.value(forHTTPHeaderField: "Cookie")
            XCTAssertTrue(cookieHeader?.contains("persist-sid") == true,
                          "Cold-restored web session must forward cookies on first probe")
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        await restored.restoreOnLaunch()
        XCTAssertEqual(restored.state, .loggedIn)
        XCTAssertEqual(restored.config.account, "")
        restored.setRememberSession(false)
        XCTAssertNil(KeychainStorage.authSession(for: "web@\(config.baseURL!.absoluteString)"))
        await restored.logout()
    }

    func testWrongOTPAndTransportFailureKeepChallengeAndCredentials() async {
        let client = await client()
        let store = SessionStore(client: client)
        AuthMockProtocol.handler = { _ in #"{"success":false,"error":{"code":403}}"# }
        await store.login(config: config, password: "password")
        XCTAssertEqual(store.state, .twoFactorRequired)
        AuthMockProtocol.handler = { _ in #"{"success":false,"error":{"code":404}}"# }
        await store.submitOTP("123456")
        XCTAssertEqual(store.state, .twoFactorRequired)
        XCTAssertNotNil(store.otpError)
        AuthMockProtocol.handler = { _ in throw URLError(.timedOut) }
        await store.submitOTP("234567")
        XCTAssertEqual(store.state, .twoFactorRequired)
        XCTAssertFalse(store.isVerifyingOTP)
        AuthMockProtocol.handler = { request in
            XCTAssertTrue(AuthMockProtocol.body(request).contains("passwd=password"))
            return #"{"success":true,"data":{"sid":"verified"}}"#
        }
        await store.submitOTP("345678")
        XCTAssertEqual(store.state, .loggedIn)
        AuthMockProtocol.handler = { _ in #"{"success":true}"# }
        await store.logout()
    }

    // MARK: - Cookie isolation tests

    /// Production SynologyAPIClient init must disconnect the cookie jar.
    /// If someone reverts `httpCookieStorage = nil` in init(), this fails.
    func testProductionClientCookieJarIsDisabled() async {
        let client = SynologyAPIClient()
        let disabled = await client.cookieStorageDisabled
        XCTAssertTrue(disabled,
                      "Production init must set httpCookieStorage = nil to prevent the OTP login loop")
    }

    /// Native OTP login must never attach a Cookie header on subsequent
    /// API calls, even when the server sends Set-Cookie on auth.cgi.
    /// The mock returns a real Set-Cookie header (not headerFields:nil)
    /// so cookie storage — if present — would capture it.
    func testNativeLoginDoesNotSendCookieOnSubsequentCalls() async throws {
        let client = await client()
        await client.configure(baseURL: config.baseURL!)

        AuthMockProtocol.responseHeaders = [
            "Set-Cookie": "id=stale-web-sid; path=/; domain=auth-tests.invalid"
        ]
        AuthMockProtocol.handler = { _ in
            return #"{"success":true,"data":{"sid":"otp-sid"}}"#
        }
        try await client.login(account: "user", password: "pass", otpCode: "123456")
        await client.clearAuthCookies()
        AuthMockProtocol.responseHeaders = nil

        AuthMockProtocol.handler = { request in
            let cookieHeader = request.value(forHTTPHeaderField: "Cookie")
            XCTAssertNil(cookieHeader, "Cookie header must not be sent on native API calls")
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        _ = try await client.listTasks()
        let hasCookies = await client.hasWebCookies
        XCTAssertFalse(hasCookies, "Native login must not populate webCookies")
    }

    /// Web sessions: cookies passed via restoreSession(_:cookies:) must
    /// arrive on subsequent API calls as a Cookie header so DSM
    /// endpoints that require cookie context receive them.
    func testWebSessionSendsCookieOnApiCalls() async throws {
        let client = await client()
        let webCookie = HTTPCookie(properties: [
            .name: "id", .value: "web-session-sid",
            .domain: "auth-tests.invalid", .path: "/webapi/",
        ])!
        await client.restoreSession(
            AuthSession(sid: "web-sid", synoToken: "csrf"),
            cookies: [webCookie]
        )

        AuthMockProtocol.handler = { request in
            let cookieHeader = request.value(forHTTPHeaderField: "Cookie")
            XCTAssertNotNil(cookieHeader, "Web session must attach Cookie header")
            XCTAssertTrue(cookieHeader?.contains("web-session-sid") == true)
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        _ = try await client.listTasks()
    }

    /// clearSession must drop web cookies so a subsequent native login
    /// doesn't inherit them.
    func testClearSessionDropsWebCookies() async throws {
        let client = await client()
        let webCookie = HTTPCookie(properties: [
            .name: "id", .value: "web-sid",
            .domain: "auth-tests.invalid", .path: "/",
        ])!
        await client.restoreSession(
            AuthSession(sid: "web", synoToken: nil),
            cookies: [webCookie]
        )
        let before = await client.hasWebCookies
        XCTAssertTrue(before)
        await client.clearSession()
        let after = await client.hasWebCookies
        XCTAssertFalse(after)
    }

    /// completeWebSignIn must pass cookies through to the API probe so
    /// the server receives them alongside _sid.
    func testWebProbeForwardsCookiesToServer() async throws {
        let client = await client()
        let store = SessionStore(client: client)
        let webCookie = HTTPCookie(properties: [
            .name: "id", .value: "web-probe-sid",
            .domain: "auth-tests.invalid", .path: "/",
        ])!

        AuthMockProtocol.handler = { request in
            let cookieHeader = request.value(forHTTPHeaderField: "Cookie")
            XCTAssertNotNil(cookieHeader, "Web probe must send cookies")
            XCTAssertTrue(cookieHeader?.contains("web-probe-sid") == true,
                          "Web probe cookie must contain the id value")
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        await store.completeWebSignIn(
            config: config,
            auth: AuthSession(sid: "web-probe-sid", synoToken: "csrf"),
            cookies: [webCookie]
        )
        XCTAssertEqual(store.state, .loggedIn)
        await store.logout()
    }

    // MARK: - handleUnauthorized re-entry guard

    /// Error 105 during an in-flight handleUnauthorized recovery must
    /// not start a second login attempt — the re-entry guard blocks it.
    /// With a stored password, recovery attempts a silent re-login; the
    /// guard must prevent a second concurrent attempt.
    ///
    /// The session is marked Download-Station-confirmed first, so this
    /// models a genuine later expiry rather than the fresh-login case
    /// the OTP-loop cycle breaker owns (see
    /// `testFresh105AfterOTPDoesNotRePromptForCode`).
    func testHandleUnauthorizedBlocksReentry() async {
        UserDefaults.standard.set(true, forKey: PasswordPersistenceSettings.storageKey)
        let client = await client()
        let store = SessionStore(client: client)

        // Log in with stored password so handleUnauthorized can attempt
        // silent re-auth.
        AuthMockProtocol.handler = { _ in #"{"success":true,"data":{"sid":"initial"}}"# }
        await store.login(config: config, password: "pass")
        XCTAssertEqual(store.state, .loggedIn)
        store.noteDownloadStationSuccess()

        // Track how many login calls recovery makes.
        var loginCount = 0
        AuthMockProtocol.handler = { request in
            let body = AuthMockProtocol.body(request)
            if body.contains("method=login") {
                loginCount += 1
                return #"{"success":false,"error":{"code":403}}"#
            }
            return #"{"success":true}"#
        }

        store.handleUnauthorized(reason: "105 first")
        store.handleUnauthorized(reason: "105 second")

        await Task.yield()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(loginCount, 1, "Re-entry guard must allow only one recovery login")
        guard case .twoFactorRequired = store.state else {
            return XCTFail("Expected .twoFactorRequired after stored-password reauth, got \(store.state)")
        }

        // Clean up — cancel 2FA and logout
        store.cancelTwoFactor()
        UserDefaults.standard.set(false, forKey: PasswordPersistenceSettings.storageKey)
    }

    /// handleUnauthorized must not fire from .restoring or
    /// .twoFactorRequired — only from .loggedIn.
    func testHandleUnauthorizedOnlyFiresFromLoggedIn() async {
        let client = await client()
        let store = SessionStore(client: client)

        store.handleUnauthorized(reason: "should be ignored")
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.state, .restoring)
    }

    // MARK: - 105 recovery with stored password doesn't double-login

    /// A single 105 on a session Download Station had already served
    /// must produce exactly one login call, land on .twoFactorRequired,
    /// then complete with a valid OTP — no double login, no loop.
    func testStoredPasswordRecoveryLoginsThenOTP() async throws {
        UserDefaults.standard.set(true, forKey: PasswordPersistenceSettings.storageKey)
        let client = await client()
        let store = SessionStore(client: client)

        AuthMockProtocol.handler = { _ in #"{"success":true,"data":{"sid":"initial"}}"# }
        await store.login(config: config, password: "secret")
        XCTAssertEqual(store.state, .loggedIn)
        store.noteDownloadStationSuccess()

        var loginCount = 0
        AuthMockProtocol.handler = { request in
            let body = AuthMockProtocol.body(request)
            if body.contains("method=login") {
                loginCount += 1
                XCTAssertTrue(body.contains("passwd=secret"), "Recovery must use stored password")
                return #"{"success":false,"error":{"code":403}}"#
            }
            return #"{"success":true}"#
        }

        store.handleUnauthorized(reason: "error 105")
        await Task.yield()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(loginCount, 1, "Exactly one recovery login expected")
        XCTAssertEqual(store.state, .twoFactorRequired)

        AuthMockProtocol.handler = { _ in #"{"success":true,"data":{"sid":"recovered"}}"# }
        await store.submitOTP("123456")
        XCTAssertEqual(store.state, .loggedIn)

        AuthMockProtocol.handler = { _ in #"{"success":true}"# }
        await store.logout()
        UserDefaults.standard.set(false, forKey: PasswordPersistenceSettings.storageKey)
    }

    /// A native credential login must not inherit cookies the client
    /// is still holding from an earlier web sign-in.
    ///
    /// `clearAuthCookies()` only scrubs `HTTPCookieStorage.shared` — it
    /// never touches the client's own `webCookies` array, which
    /// `attachWebCookies` hand-writes into the `Cookie` header. So a
    /// leftover web `id` cookie would ride along with the new native
    /// `_sid`, rebuilding the exact conflict #25 removed, on a
    /// transport where neither `httpCookieStorage = nil` nor the
    /// shared-jar cleanup can catch it.
    func testNativeLoginDropsLeftoverWebCookies() async throws {
        let client = await client()
        await client.restoreSession(AuthSession(sid: "web", synoToken: "csrf"), cookies: [webCookie(value: "stale-web-sid")])
        let heldBefore = await client.hasWebCookies
        XCTAssertTrue(heldBefore)

        AuthMockProtocol.handler = { _ in #"{"success":true,"data":{"sid":"native-sid"}}"# }
        try await client.login(account: "user", password: "pass", otpCode: "123456")
        let heldAfter = await client.hasWebCookies
        XCTAssertFalse(heldAfter, "Native login must not inherit web cookies")

        AuthMockProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"),
                         "Stale web cookie must not ride along with the new native _sid")
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        _ = try await client.listTasks()
    }

    /// The same isolation at the SessionStore level: signing in from
    /// the form while the client still holds a web session must clear
    /// it before the login request goes out.
    func testFormLoginClearsHeldWebSessionFirst() async {
        let client = await client()
        let store = SessionStore(client: client)
        await client.restoreSession(AuthSession(sid: "web", synoToken: "csrf"), cookies: [webCookie(value: "leftover")])

        AuthMockProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"),
                         "Form sign-in must go out on a clean transport")
            return #"{"success":true,"data":{"sid":"native"}}"#
        }
        await store.login(config: config, password: "pass")
        XCTAssertEqual(store.state, .loggedIn)
        let held = await client.hasWebCookies
        XCTAssertFalse(held)
    }

    /// Pointing the client at a different NAS must drop the previous
    /// server's cookies along with its SID.
    func testConfigureToNewHostDropsCookies() async {
        let client = await client()
        await client.restoreSession(AuthSession(sid: "web"), cookies: [webCookie()])
        await client.configure(baseURL: URL(string: "https://other-nas.invalid:5001")!)
        let held = await client.hasWebCookies
        let loggedIn = await client.isLoggedIn
        XCTAssertFalse(held)
        XCTAssertFalse(loggedIn)
    }

    /// Cold restore of a *native* session must not rehydrate cookies
    /// from the keychain, even if a record exists there (an older build
    /// under the same account slot, a hand-edited keychain). A native
    /// session is `_sid`-only by contract.
    func testNativeColdRestoreIgnoresStoredCookies() async throws {
        UserDefaults.standard.set(true, forKey: RememberSessionSettings.storageKey)
        defer { UserDefaults.standard.set(false, forKey: RememberSessionSettings.storageKey) }
        let key = "native-user@\(config.host)"
        try KeychainStorage.setAuthSession(AuthSession(sid: "stored"), for: key)
        try KeychainStorage.setCookies([StoredCookie(cookie: webCookie(value: "legacy-native-cookie"))], for: key)
        ServerConfigStore.save(config)
        defer {
            KeychainStorage.deleteSID(for: key)
            KeychainStorage.deleteCookies(for: key)
            KeychainStorage.deleteSessionMetadata(for: key)
            ServerConfigStore.clear()
        }

        let client = await client()
        let store = SessionStore(client: client)
        AuthMockProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"),
                         "Native cold restore must not send stored cookies")
            return #"{"success":true,"data":{"tasks":[]}}"#
        }
        await store.restoreOnLaunch()
        XCTAssertEqual(store.state, .loggedIn)
        let held = await client.hasWebCookies
        XCTAssertFalse(held)
    }

    // MARK: - OTP re-prompt loop (the r2 regression)

    /// The reported loop, end to end: credentials → 403 → OTP → login
    /// succeeds → Download Station answers the very first poll with
    /// 105. The old behaviour silently re-logged-in with the stored
    /// password and landed back on `.twoFactorRequired`, so the user
    /// saw the dashboard flash and got the code screen again, forever.
    ///
    /// The fresh session's credentials were just verified by DSM, so a
    /// re-login cannot help. We must land on the recovery card and
    /// issue no further login request.
    func testFresh105AfterOTPDoesNotRePromptForCode() async {
        UserDefaults.standard.set(true, forKey: PasswordPersistenceSettings.storageKey)
        defer { UserDefaults.standard.set(false, forKey: PasswordPersistenceSettings.storageKey) }
        let client = await client()
        let store = SessionStore(client: client)

        var loginCount = 0
        AuthMockProtocol.handler = { request in
            let body = AuthMockProtocol.body(request)
            if body.contains("method=login") {
                loginCount += 1
                return loginCount == 1
                    ? #"{"success":false,"error":{"code":403}}"#
                    : #"{"success":true,"data":{"sid":"fresh-otp-sid"}}"#
            }
            return #"{"success":true}"#
        }
        await store.login(config: config, password: "secret")
        XCTAssertEqual(store.state, .twoFactorRequired)
        await store.submitOTP("123456")
        XCTAssertEqual(store.state, .loggedIn)
        XCTAssertEqual(loginCount, 2)

        // First Download Station poll on the brand-new session: 105.
        store.handleUnauthorized(reason: "Synology error 105")
        await Task.yield()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(loginCount, 2,
                       "A fresh, just-verified session must not trigger another login")
        guard case .sessionUnauthorized = store.state else {
            return XCTFail("Expected the recovery card, got \(store.state) — the OTP loop is back")
        }
        XCTAssertTrue(store.isPermissionRecovery,
                      "Card must read as a Download Station permission problem, not an expiry")
    }

    /// The loop's other entry point: cold launch with a stored SID that
    /// DSM rejects. There, a silent re-login *is* the right recovery
    /// (the SID is genuinely old), so we still prompt for one code —
    /// but once that code succeeds and Download Station still says 105,
    /// the chain must stop rather than ask for a second code.
    func testColdRestore105PromptsForCodeExactlyOnce() async throws {
        UserDefaults.standard.set(true, forKey: RememberSessionSettings.storageKey)
        UserDefaults.standard.set(true, forKey: PasswordPersistenceSettings.storageKey)
        defer {
            UserDefaults.standard.set(false, forKey: RememberSessionSettings.storageKey)
            UserDefaults.standard.set(false, forKey: PasswordPersistenceSettings.storageKey)
        }
        try KeychainStorage.setAuthSession(AuthSession(sid: "stale"), for: "native-user@\(config.host)")
        try KeychainStorage.setPassword("secret", for: config.account)
        ServerConfigStore.save(config)
        defer {
            KeychainStorage.deleteSID(for: "native-user@\(config.host)")
            KeychainStorage.deletePassword(for: config.account)
            KeychainStorage.deleteSessionMetadata(for: "native-user@\(config.host)")
            ServerConfigStore.clear()
        }

        let client = await client()
        let store = SessionStore(client: client)
        var loginCount = 0
        AuthMockProtocol.handler = { request in
            let body = AuthMockProtocol.body(request)
            if body.contains("method=login") {
                loginCount += 1
                return #"{"success":false,"error":{"code":403}}"#
            }
            // Download Station rejects everything for this account.
            return #"{"success":false,"error":{"code":105}}"#
        }
        await store.restoreOnLaunch()

        // Stale SID rejected → one silent re-login → one code prompt.
        XCTAssertEqual(loginCount, 1)
        XCTAssertEqual(store.state, .twoFactorRequired)

        AuthMockProtocol.handler = { request in
            let body = AuthMockProtocol.body(request)
            if body.contains("method=login") {
                loginCount += 1
                return #"{"success":true,"data":{"sid":"recovered"}}"#
            }
            return #"{"success":false,"error":{"code":105}}"#
        }
        await store.submitOTP("123456")
        XCTAssertEqual(store.state, .loggedIn)

        store.handleUnauthorized(reason: "Synology error 105")
        await Task.yield()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(loginCount, 2, "Exactly one code prompt, then stop")
        guard case .sessionUnauthorized = store.state else {
            return XCTFail("Expected the recovery card, got \(store.state)")
        }
    }

    /// The cycle breaker must not cost us the useful recovery: a
    /// session that Download Station has actually served (a successful
    /// poll) and which later expires still gets the silent re-login →
    /// OTP-only prompt.
    func testConfirmedSessionStillGetsSilentReauthOnLaterExpiry() async {
        UserDefaults.standard.set(true, forKey: PasswordPersistenceSettings.storageKey)
        defer { UserDefaults.standard.set(false, forKey: PasswordPersistenceSettings.storageKey) }
        let client = await client()
        let store = SessionStore(client: client)

        AuthMockProtocol.handler = { _ in #"{"success":true,"data":{"sid":"good"}}"# }
        await store.login(config: config, password: "secret")
        XCTAssertEqual(store.state, .loggedIn)

        // A poll succeeded — Download Station accepts this session.
        store.noteDownloadStationSuccess()

        var loginCount = 0
        AuthMockProtocol.handler = { request in
            if AuthMockProtocol.body(request).contains("method=login") {
                loginCount += 1
                return #"{"success":false,"error":{"code":403}}"#
            }
            return #"{"success":true}"#
        }
        store.handleUnauthorized(reason: "Synology error 106")
        await Task.yield()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(loginCount, 1, "A previously-good session still re-auths silently")
        XCTAssertEqual(store.state, .twoFactorRequired)
        XCTAssertFalse(store.isPermissionRecovery)
        store.cancelTwoFactor()
    }

    /// A successful poll reported through `DownloadTaskStore`'s
    /// `onAuthorized` callback must be what clears the breaker — the
    /// wiring, not just the SessionStore method.
    func testTaskStoreReportsSuccessfulPollAsAuthorized() async {
        let client = await client()
        var authorizedCount = 0
        let store = DownloadTaskStore(client: client, onAuthorized: { authorizedCount += 1 })
        await client.restoreSession(AuthSession(sid: "sid"))

        AuthMockProtocol.handler = { _ in #"{"success":true,"data":{"tasks":[]}}"# }
        await store.refresh()
        XCTAssertEqual(authorizedCount, 1)

        AuthMockProtocol.handler = { _ in #"{"success":false,"error":{"code":105}}"# }
        await store.refresh()
        XCTAssertEqual(authorizedCount, 1, "A 105 poll must not report success")
    }

    // MARK: - Case-insensitive cookie cleanup

    /// clearAuthCookies must remove cookies regardless of domain case.
    func testClearAuthCookiesCaseInsensitive() async {
        let client = SynologyAPIClient()
        let mixedCaseConfig = ServerConfig(scheme: .https, host: "NAS.local", port: 5001, account: "user")
        await client.configure(baseURL: mixedCaseConfig.baseURL!)

        let storage = HTTPCookieStorage.shared
        let cookie = HTTPCookie(properties: [
            .name: "id",
            .value: "stale-sid",
            .domain: "nas.local",
            .path: "/",
        ])!
        storage.setCookie(cookie)

        await client.clearAuthCookies()

        let remaining = storage.cookies?.filter { $0.name == "id" && $0.domain == "nas.local" } ?? []
        XCTAssertTrue(remaining.isEmpty, "Cookie with lowercase domain must be removed when host is uppercase")
    }
}
