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

    /// Settings can be reached from both the task list (logged in) and the login
    /// screen (logged out). Hide account controls in the latter case — they would
    /// just sign-out an already-signed-out session.
    private var isSignedIn: Bool {
        session.state == .loggedIn
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                if isSignedIn { accountSection }
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
                Text("Removes the saved password and session from the Keychain. Next sign-in will ask for your password and any 2FA code from scratch.")
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
            Text("Sign out keeps your saved password for next time. Forget clears the password too.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "DropStation")
            LabeledContent("Version", value: Self.versionString)
            NavigationLink {
                ChangelogView()
            } label: {
                Label("What's new", systemImage: "sparkles")
            }
            Link(destination: URL(string: "https://github.com/Wenzlik/DropStation")!) {
                Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
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
