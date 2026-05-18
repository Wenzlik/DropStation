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
                    await session.reauthenticate()
                    dismiss()
                }
            } label: {
                Label("Re-authenticate now", systemImage: "arrow.clockwise.circle")
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
            Text("Re-authenticate triggers a fresh 2FA challenge using your saved password. Sign out keeps the password for next time. Forget clears the password too.")
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
