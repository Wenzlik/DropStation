import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue
    @State private var confirmForget = false

    private var appearance: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                accountSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Forget this device?", isPresented: $confirmForget) {
                Button("Forget", role: .destructive) {
                    Task {
                        await session.forgetDevice()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the saved password, session, and 2FA device trust from the Keychain. You will have to re-enter your 2FA code next time.")
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker(selection: appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            } label: {
                Label("Theme", systemImage: "paintpalette")
            }
            .pickerStyle(.inline)
        }
    }

    private var accountSection: some View {
        Section {
            if !session.config.account.isEmpty, !session.config.host.isEmpty {
                LabeledContent("Signed in as", value: "\(session.config.account)@\(session.config.host)")
            }
            if session.hasTrustedDevice {
                Label("2FA device trust active", systemImage: "checkmark.shield")
                    .foregroundStyle(.green)
            }
            Button {
                Task {
                    await session.logout()
                    dismiss()
                }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button(role: .destructive) {
                confirmForget = true
            } label: {
                Label("Forget this device", systemImage: "trash")
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Sign out keeps your password and 2FA trust on this device for next time. Forget clears everything.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Syno Get")
            LabeledContent("Version", value: Self.versionString)
            Link(destination: URL(string: "https://github.com/Wenzlik/SynoGet")!) {
                Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: URL(string: "https://github.com/keyfun/synology_ds_get")!) {
                Label("Based on keyfun/synology_ds_get", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Helpers

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
