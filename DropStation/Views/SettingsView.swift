import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @AppStorage(AppearanceSettings.storageKey) private var appearanceRaw: String = AppearanceMode.system.rawValue
    @AppStorage(RememberSessionSettings.storageKey) private var rememberSession: Bool = true
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
                privacySection
                feedbackSection
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
                Text("Removes the saved session from the Keychain. Next sign-in will ask for your password and any 2FA code from scratch.")
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
            Text("Sign out clears the saved session. Forget this device additionally removes any legacy credentials older builds may have stored.")
        }
    }

    /// Controls credential persistence. Default ON: the app caches the
    /// Download Station SID in the Keychain so cold starts can skip the
    /// OTP prompt. Switching OFF clears every saved credential we hold
    /// for the current account (SID, cookies, metadata, password). The
    /// active in-memory session keeps working until the next launch.
    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { rememberSession },
                set: { newValue in
                    rememberSession = newValue
                    session.setRememberSession(newValue)
                }
            )) {
                Label("Remember session", systemImage: "lock.rotation")
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text(rememberSession
                ? "Your SID is stored in the iOS Keychain so the app stays signed in across launches."
                : "Saved credentials are removed. You'll need to sign in every time you open the app.")
        }
    }

    private var feedbackSection: some View {
        // Opens GitHub's "New issue" page with the matching template pre-
        // selected. The user needs a GitHub account to actually post — that's
        // handled by github.com, we just deep-link the right form.
        Section {
            Link(destination: URL(string: "https://github.com/Wenzlik/DropStation/issues/new?template=feature_request.md")!) {
                Label("Suggest a feature", systemImage: "lightbulb")
            }
            Link(destination: URL(string: "https://github.com/Wenzlik/DropStation/issues/new?template=bug_report.md")!) {
                Label("Report a bug", systemImage: "ladybug")
            }
        } header: {
            Text("Feedback")
        } footer: {
            Text("Opens GitHub in Safari. A GitHub account is required to post.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("App", value: "DropStation")
            // Tappable Version row: the value reads as plain text but the
            // whole row pushes the in-app changelog. A chevron makes the
            // affordance discoverable without an extra "What's new" entry.
            NavigationLink {
                ChangelogView()
            } label: {
                LabeledContent("Version", value: Self.versionString)
            }
            Link(destination: URL(string: "https://github.com/Wenzlik")!) {
                Label("Made by @Wenzlik", systemImage: "person.circle")
            }
            Link(destination: URL(string: "https://github.com/Wenzlik/DropStation")!) {
                Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } header: {
            Text("About")
        } footer: {
            Text("© 2026 Vasek Zmrhal · MIT License")
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
