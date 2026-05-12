import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var scheme: ServerConfig.Scheme = .https
    @State private var host: String = ""
    @State private var port: String = "5001"
    @State private var account: String = ""
    @State private var password: String = ""
    @State private var otpCode: String = ""
    @State private var useOTP: Bool = false
    @State private var trustThisDevice: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    Picker("Scheme", selection: $scheme) {
                        ForEach(ServerConfig.Scheme.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField("Host (e.g. nas.local or 192.168.1.10)", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }

                Section {
                    TextField("Username", text: $account)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                } header: {
                    Text("Account")
                } footer: {
                    if session.hasTrustedDevice {
                        Label("This device is trusted — 2-step verification not needed.",
                              systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }

                // Hide 2FA controls entirely when the server already trusts this device for
                // the current account+host. Show them otherwise so the user can complete the
                // 2FA challenge and (by default) trust the device for next time.
                if !session.hasTrustedDevice {
                    Section {
                        Toggle("Two-step verification", isOn: $useOTP)
                        if useOTP {
                            TextField("6-digit code", text: $otpCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Toggle("Trust this device (skip 2FA next time)",
                                   isOn: $trustThisDevice)
                        }
                    }
                }

                if case .error(let message) = session.state {
                    Section { Text(message).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        if case .authenticating = session.state {
                            ProgressView()
                        } else {
                            Text("Sign in")
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Syno Get")
            .onAppear(perform: prefill)
        }
    }

    private var canSubmit: Bool {
        !host.isEmpty && !account.isEmpty && !password.isEmpty && Int(port) != nil
    }

    private func prefill() {
        let cfg = session.config
        scheme = cfg.scheme
        host = cfg.host
        port = String(cfg.port)
        account = cfg.account
        if !account.isEmpty, let saved = KeychainStorage.password(for: account) {
            password = saved
        }
    }

    private func login() async {
        guard let portInt = Int(port) else { return }
        let cfg = ServerConfig(scheme: scheme, host: host, port: portInt, account: account)
        let otp = (!session.hasTrustedDevice && useOTP) ? otpCode : nil
        await session.login(config: cfg, password: password, otpCode: otp, trustThisDevice: trustThisDevice)
    }
}
