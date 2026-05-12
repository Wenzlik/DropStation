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

                Section("Account") {
                    TextField("Username", text: $account)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)

                    Toggle("Two-step verification", isOn: $useOTP)
                    if useOTP {
                        TextField("6-digit code", text: $otpCode)
                            .keyboardType(.numberPad)
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
            .navigationTitle("Synology Torrent")
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
        await session.login(config: cfg, password: password, otpCode: useOTP ? otpCode : nil)
    }
}
