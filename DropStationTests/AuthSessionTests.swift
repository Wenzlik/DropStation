import XCTest
@testable import DropStation

private final class AuthMockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> String)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let body = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
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
    }

    private func client() async -> SynologyAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthMockProtocol.self]
        configuration.httpCookieStorage = nil
        let client = SynologyAPIClient(session: URLSession(configuration: configuration))
        await client.configure(baseURL: config.baseURL!)
        return client
    }

    func testTokenReachesDS1DS2FileStationAndMultipart() async throws {
        let client = await client()
        await client.restoreSession(AuthSession(sid: "sid", synoToken: "csrf&+="))
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

    /// Production SynologyAPIClient (not test-seam) must never attach a
    /// Cookie header on native OTP API calls, even when an `id` cookie
    /// sits in the shared jar. This is the root cause of the OTP loop.
    func testNativeLoginDoesNotSendCookieOnSubsequentCalls() async throws {
        let client = await client()
        await client.configure(baseURL: config.baseURL!)

        AuthMockProtocol.handler = { request in
            let headers = HTTPCookie.requestHeaderFields(with: [
                HTTPCookie(properties: [
                    .name: "id", .value: "stale-web-sid",
                    .domain: "auth-tests.invalid", .path: "/",
                ])!
            ])
            var response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
            _ = response
            return #"{"success":true,"data":{"sid":"otp-sid"}}"#
        }
        try await client.login(account: "user", password: "pass", otpCode: "123456")
        await client.clearAuthCookies()

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
    func testHandleUnauthorizedBlocksReentry() async {
        UserDefaults.standard.set(true, forKey: PasswordPersistenceSettings.storageKey)
        let client = await client()
        let store = SessionStore(client: client)

        // Log in with stored password so handleUnauthorized can attempt
        // silent re-auth.
        AuthMockProtocol.handler = { _ in #"{"success":true,"data":{"sid":"initial"}}"# }
        await store.login(config: config, password: "pass")
        XCTAssertEqual(store.state, .loggedIn)

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

    /// A single 105 with a stored password must produce exactly one
    /// login call, land on .twoFactorRequired, then complete with a
    /// valid OTP — no double login, no loop.
    func testStoredPasswordRecoveryLoginsThenOTP() async throws {
        UserDefaults.standard.set(true, forKey: PasswordPersistenceSettings.storageKey)
        let client = await client()
        let store = SessionStore(client: client)

        AuthMockProtocol.handler = { _ in #"{"success":true,"data":{"sid":"initial"}}"# }
        await store.login(config: config, password: "secret")
        XCTAssertEqual(store.state, .loggedIn)

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
