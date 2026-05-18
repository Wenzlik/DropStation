import SwiftUI
@preconcurrency import WebKit

/// Sheet-mounted DSM web sign-in. Loads the NAS login page in a
/// `WKWebView`, lets the user complete the full Synology web flow there
/// (username + password + push approval / OTP / whatever the account is
/// configured for), then detects post-login state and harvests the
/// session cookies for the host app.
///
/// We deliberately do not try to scrape or replay the JS-driven Secure
/// SignIn endpoints — that's the rabbit hole the 0.3.2 push-polling
/// attempt fell into. Instead the DSM web UI runs unchanged, exactly as
/// it would in Safari, and we just grab the resulting cookies once the
/// user has landed on a logged-in page.
///
/// "Logged in" is detected heuristically: after a successful sign-in
/// DSM navigates to `/index.cgi` / `/?launchApp=...` / a hash route
/// like `/#desktop` — anything that isn't the login page. We also
/// require the cookie jar to contain a Synology session cookie (`id`,
/// the DSM SID) before declaring success, so an intermediate
/// password-stage redirect doesn't fire the callback prematurely.
struct SecureSignInWebView: View {
    let loginURL: URL
    /// Called once the user has successfully signed in. Hands back the
    /// cookies the web view collected for the DSM host plus the SID
    /// extracted from the `id` cookie (DSM stores the session id there
    /// when accessed via the web UI). The host scrim is dismissed
    /// immediately after this fires.
    let onSuccess: (_ sid: String, _ cookies: [HTTPCookie]) -> Void
    /// Called when the user backs out without signing in.
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            WebViewContainer(loginURL: loginURL, onSuccess: onSuccess)
                .ignoresSafeArea(.container, edges: .bottom)
                .navigationTitle("Sign in to NAS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel", role: .cancel) {
                            onCancel()
                        }
                    }
                }
        }
    }
}

/// UIViewRepresentable wrapper around `WKWebView`. Keeps the
/// `WKNavigationDelegate` lifetime tied to the SwiftUI view via the
/// `Coordinator`.
private struct WebViewContainer: UIViewRepresentable {
    let loginURL: URL
    let onSuccess: (_ sid: String, _ cookies: [HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(loginURL: loginURL, onSuccess: onSuccess)
    }

    func makeUIView(context: Context) -> WKWebView {
        // Use a non-persistent data store so the web view doesn't leak
        // cookies across users / NASes — every sheet starts with a clean
        // jar. We promote the harvested cookies into our own session
        // store after sign-in succeeds; what stays in WKWebView's own
        // storage is irrelevant.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Some DSM builds reject "non-browser" User-Agents and refuse to
        // serve the Secure SignIn JS, so present ourselves as Safari
        // mobile. The string itself isn't load-bearing beyond "look like
        // a real browser".
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

        webView.load(URLRequest(url: loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No-op — the coordinator owns mutable state.
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let loginURL: URL
        let onSuccess: (_ sid: String, _ cookies: [HTTPCookie]) -> Void
        weak var webView: WKWebView?
        /// Once we've called `onSuccess` we want the delegate to stay
        /// quiet — further navigation events would only race the parent
        /// dismissing the sheet.
        private var didFinish: Bool = false

        init(loginURL: URL, onSuccess: @escaping (String, [HTTPCookie]) -> Void) {
            self.loginURL = loginURL
            self.onSuccess = onSuccess
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didFinish else { return }
            // After every page load, check whether we're past the login
            // screen. DSM's web entry is `/webman/index.cgi` (DSM 7) or
            // `/?launchApp=...` redirects; the login page itself lives
            // at `/`, `/index.cgi`, or `/webman/login.cgi`. We treat
            // "not a known login URL AND has a session cookie" as
            // success.
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.checkForCompletion()
            }
        }

        @MainActor
        private func checkForCompletion() async {
            guard let webView, !didFinish else { return }
            guard let url = webView.url else { return }

            // Heuristic: the login-form URL contains "login.cgi" or the
            // path is exactly "/" with no query. After sign-in DSM
            // navigates to `/index.cgi?launchApp=...` or `/webman/`
            // followed by a hash-route into the desktop. Anything else
            // and we should check the cookie jar.
            let path = url.path.lowercased()
            let isOnLoginPage = path.contains("login.cgi") || path.contains("/webman/login")
            if isOnLoginPage { return }

            let dataStore = webView.configuration.websiteDataStore
            let cookies = await dataStore.httpCookieStore.allCookies()
            guard let host = loginURL.host else { return }
            let hostCookies = cookies.filter { cookieMatches(host: host, cookie: $0) }
            guard let idCookie = hostCookies.first(where: { $0.name == "id" }) else { return }

            didFinish = true
            onSuccess(idCookie.value, hostCookies)
        }

        private func cookieMatches(host: String, cookie: HTTPCookie) -> Bool {
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}
