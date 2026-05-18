import SwiftUI

/// Synology-DSM-inspired login screen: centered card with a single column of fields
/// (username, password, optional server config disclosure) and one big Sign in button.
/// After the first attempt the same card switches to a 2FA challenge layout when the
/// server demands a second factor.
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    /// Persisted across launches so a returning user lands on the same
    /// auth flow they last used (OTP vs. Secure SignIn web).
    @AppStorage(AuthMethodSettings.storageKey) private var authMethodRaw: String = AuthMethod.otp.rawValue
    private var authMethod: Binding<AuthMethod> {
        Binding(
            get: { AuthMethod(rawValue: authMethodRaw) ?? .otp },
            set: { authMethodRaw = $0.rawValue }
        )
    }

    @State private var scheme: ServerConfig.Scheme = .https
    @State private var host: String = ""
    @State private var port: String = "5001"
    @State private var account: String = ""
    @State private var password: String = ""
    @State private var otpCode: String = ""
    @State private var serverExpanded: Bool = false
    @State private var showingSettings: Bool = false
    /// Presents the WKWebView-backed DSM sign-in sheet. Carries the
    /// computed login URL so the sheet can build itself without
    /// re-doing the host/scheme/port arithmetic. Wrapped in
    /// `IdentifiableURL` because `.sheet(item:)` requires `Identifiable`.
    @State private var webSignInURL: IdentifiableURL?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    header
                    card
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            settingsButton
        }
        .onAppear(perform: prefill)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $webSignInURL) { wrapped in
            SecureSignInWebView(
                loginURL: wrapped.url,
                onSuccess: { sid, cookies in
                    let captured = ServerConfig(
                        scheme: scheme,
                        host: host,
                        port: Int(port) ?? 5001,
                        // The web flow doesn't expose which DSM user
                        // signed in — DSM identifies the session purely
                        // by SID at this point. Fall back to whatever
                        // the user typed in the (now-hidden) form, or
                        // an empty string if they used Secure SignIn
                        // straight off the bat. The session probe will
                        // populate state from the actual user later.
                        account: account
                    )
                    webSignInURL = nil
                    Task {
                        await session.completeWebSignIn(
                            config: captured,
                            sid: sid,
                            cookies: cookies
                        )
                    }
                },
                onCancel: {
                    webSignInURL = nil
                }
            )
        }
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(12)
                .glassEffect(.regular, in: .circle)
        }
        .padding(.top, 8)
        .padding(.trailing, 16)
        .accessibilityLabel("Settings")
    }

    // MARK: - Header

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.to.line.compact")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .foregroundStyle(.white)
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.69, blue: 0.24),
                                 Color(red: 0.94, green: 0.54, blue: 0.11)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            Text("DropStation").font(.largeTitle.weight(.semibold))
            Text(welcomeSubtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var welcomeSubtitle: String {
        if !session.config.host.isEmpty {
            return "Sign in to \(session.config.host)"
        }
        return "Sign in to your Synology Download Station"
    }

    // MARK: - Card

    @ViewBuilder
    private var card: some View {
        VStack(spacing: 16) {
            if case .twoFactorRequired = session.state {
                twoFactorContent
            } else {
                credentialsContent
            }
        }
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .animation(.easeInOut(duration: 0.25), value: session.state)
    }

    // MARK: - Credentials sub-view

    @ViewBuilder
    private var credentialsContent: some View {
        authMethodPicker

        switch authMethod.wrappedValue {
        case .otp:
            otpCredentialsContent
        case .secureSignInWeb:
            secureSignInCredentialsContent
        }
    }

    /// Compact picker that lets the user flip between the two 2FA flows
    /// before they commit credentials. Rendered as a segmented control so
    /// it stays out of the way visually but the two options are both
    /// always visible (vs. hiding one behind a menu).
    private var authMethodPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Sign-in method", selection: authMethod) {
                ForEach(AuthMethod.allCases) { method in
                    Label(method.label, systemImage: method.systemImage).tag(method)
                }
            }
            .pickerStyle(.segmented)
            Text(authMethod.wrappedValue.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 4)
    }

    /// Username + password + server config, as before. The OTP six-digit
    /// code (when required) is collected by `twoFactorContent` on a
    /// second pass through the card.
    @ViewBuilder
    private var otpCredentialsContent: some View {
        IconField(systemImage: "person.crop.circle", placeholder: "Username", text: $account)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.username)

        IconSecureField(systemImage: "lock", placeholder: "Password", text: $password)
            .textContentType(.password)

        DisclosureGroup(isExpanded: $serverExpanded) {
            serverConfigFields
        } label: {
            HStack {
                Image(systemName: "server.rack").foregroundStyle(.secondary)
                Text("Server").font(.callout)
                Spacer()
                Text(serverSummary)
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)

        if case .error(let message) = session.state {
            inlineErrorLabel(message)
        }

        signInButton(label: "Sign in", isWorking: session.state == .authenticating) {
            Task { await login() }
        }
        .disabled(!credentialsValid || session.state == .authenticating)
    }

    /// Secure SignIn web flow card. The actual sign-in (username,
    /// password, Approve sign-in push approval / OTP) runs inside the
    /// DSM web UI itself, hosted in a `WKWebView` we present as a
    /// sheet. We just collect host details here and hand off.
    @ViewBuilder
    private var secureSignInCredentialsContent: some View {
        DisclosureGroup(isExpanded: $serverExpanded) {
            serverConfigFields
        } label: {
            HStack {
                Image(systemName: "server.rack").foregroundStyle(.secondary)
                Text("Server").font(.callout)
                Spacer()
                Text(serverSummary)
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)

        Text("Tap Continue to open your NAS sign-in page. Enter your username and password there, then approve the push notification in Synology Secure SignIn.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)

        if case .error(let message) = session.state {
            inlineErrorLabel(message)
        }

        signInButton(label: "Continue to web sign-in", isWorking: false) {
            presentWebSignIn()
        }
        .disabled(!hostValid)
    }

    private var hostValid: Bool {
        !host.isEmpty && Int(port) != nil
    }

    private func presentWebSignIn() {
        guard let portInt = Int(port),
              let url = ServerConfig(scheme: scheme, host: host, port: portInt, account: account).baseURL
        else { return }
        webSignInURL = IdentifiableURL(url: url)
    }

    private var serverConfigFields: some View {
        VStack(spacing: 12) {
            Picker("Scheme", selection: $scheme) {
                ForEach(ServerConfig.Scheme.allCases) { Text($0.rawValue.uppercased()).tag($0) }
            }
            .pickerStyle(.segmented)

            IconField(systemImage: "network", placeholder: "Host or IP", text: $host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)

            IconField(systemImage: "number", placeholder: "Port", text: $port)
                .keyboardType(.numberPad)
        }
        .padding(.top, 8)
    }

    private var serverSummary: String {
        host.isEmpty ? "Not configured" : "\(scheme.rawValue)://\(host):\(port)"
    }

    private var credentialsValid: Bool {
        !host.isEmpty && !account.isEmpty && !password.isEmpty && Int(port) != nil
    }

    // MARK: - 2FA sub-view

    @ViewBuilder
    private var twoFactorContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text("Two-step verification").font(.title3.weight(.semibold))
            Text("Open your authenticator app — Synology Secure SignIn (Codes tab), Google Authenticator, 1Password, etc. — and enter the 6-digit code.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)

        IconField(systemImage: "number.square", placeholder: "6-digit code", text: $otpCode)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)

        if case .error(let message) = session.state {
            inlineErrorLabel(message)
        }

        signInButton(
            label: "Verify code",
            isWorking: session.state == .authenticating
        ) {
            Task { await session.submitOTP(otpCode) }
        }
        .disabled(otpCode.count < 6 || session.state == .authenticating)

        Button("Cancel", role: .cancel) {
            session.cancelTwoFactor()
            otpCode = ""
        }
        .font(.footnote)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Common buttons

    @ViewBuilder
    private func signInButton(label: String, isWorking: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(label).font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func inlineErrorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func prefill() {
        let cfg = session.config
        scheme = cfg.scheme
        host = cfg.host
        port = String(cfg.port)
        account = cfg.account
        serverExpanded = host.isEmpty
        if !account.isEmpty, let saved = KeychainStorage.password(for: account) {
            password = saved
        }
    }

    private func login() async {
        guard let portInt = Int(port) else { return }
        let cfg = ServerConfig(scheme: scheme, host: host, port: portInt, account: account)
        await session.login(config: cfg, password: password)
    }
}

/// `.sheet(item:)` requires the payload to be `Identifiable`. `URL`
/// isn't (and conforming it globally would risk colliding with other
/// code), so wrap it for the one place we need it.
private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Field components

private struct IconField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            TextField(placeholder, text: $text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct IconSecureField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    @State private var revealed: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            if revealed {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                SecureField(placeholder, text: $text)
            }
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
