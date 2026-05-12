import SwiftUI

/// Synology-DSM-inspired login screen: centered card with a single column of fields
/// (username, password, optional server config disclosure) and one big Sign in button.
/// After the first attempt the same card switches to a 2FA challenge layout when the
/// server demands a second factor.
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var scheme: ServerConfig.Scheme = .https
    @State private var host: String = ""
    @State private var port: String = "5001"
    @State private var account: String = ""
    @State private var password: String = ""
    @State private var trustThisDevice: Bool = true
    @State private var otpCode: String = ""
    @State private var serverExpanded: Bool = false

    var body: some View {
        ZStack {
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
        }
        .onAppear(perform: prefill)
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
            Text("Syno Get").font(.largeTitle.weight(.semibold))
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
            Text("Approve the sign-in request on your Synology Secure SignIn app, or enter the 6-digit code below.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)

        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Waiting for approval…").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)

        IconField(systemImage: "number.square", placeholder: "6-digit code", text: $otpCode)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)

        Toggle("Trust this device", isOn: $trustThisDevice)
            .font(.footnote)
            .padding(.horizontal, 4)

        signInButton(
            label: "Verify code",
            isWorking: session.state == .authenticating
        ) {
            Task { await session.submitOTP(otpCode) }
        }
        .disabled(otpCode.count < 6 || session.state == .authenticating)

        HStack {
            Button("Cancel", role: .cancel) {
                session.cancelTwoFactor()
                otpCode = ""
            }
            Spacer()
            Button("Resend push") {
                Task { await session.resendPushApproval() }
            }
        }
        .font(.footnote)
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
        await session.login(config: cfg, password: password, trustThisDevice: trustThisDevice)
    }
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
