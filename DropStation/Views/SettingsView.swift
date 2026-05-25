import SwiftUI

/// Settings rewritten to the Phase-3 design system. SwiftUI `Form`
/// dropped in favour of `ScrollView` + `DSSectionCard` so the
/// surface treatment matches the dashboard and Downloads list
/// (uppercase tracked eyebrow headers, `.regularMaterial` rounded
/// cards with a hairline border, helper text outside the card).
///
/// Phase 4.2.2 scope: section migration only — appearance,
/// privacy, account, feedback, about. The account section keeps
/// its existing list-row shape via `DSSettingsRow`; Phase 4.2.3
/// promotes it to an identity hero card with `DSAvatarCircle`.
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
            ZStack {
                backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.xl) {
                        if isSignedIn { accountSection }
                        appearanceSection
                        privacySection
                        feedbackSection
                        aboutSection
                    }
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.lg)
                }
                .scrollContentBackground(.hidden)
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

    private var accountSection: some View {
        DSSectionCard(
            "Account",
            helperText: "Sign out clears the saved session. Forget this device additionally removes any legacy credentials older builds may have stored."
        ) {
            if !session.config.account.isEmpty, !session.config.host.isEmpty {
                DSSettingsRow.value(
                    systemImage: "person.crop.circle",
                    label: "Signed in as",
                    value: "\(session.config.account)@\(session.config.host)"
                )
                rowDivider
            }
            DSSettingsRow.button(
                systemImage: "rectangle.portrait.and.arrow.right",
                label: "Sign out"
            ) {
                Task {
                    await session.logout()
                    dismiss()
                }
            }
            rowDivider
            DSSettingsRow.button(
                systemImage: "trash",
                label: "Forget this device",
                role: .destructive
            ) {
                confirmForget = true
            }
        }
    }

    private var appearanceSection: some View {
        DSSectionCard("Appearance") {
            DSSettingsRow.picker(
                systemImage: "paintpalette",
                label: "Theme",
                selection: appearance,
                options: AppearanceMode.allCases,
                optionLabel: \.label
            )
        }
    }

    /// Controls credential persistence. Default ON: the app caches the
    /// Download Station SID in the Keychain so cold starts can skip the
    /// OTP prompt. Switching OFF clears every saved credential we hold
    /// for the current account (SID, cookies, metadata, password). The
    /// active in-memory session keeps working until the next launch.
    private var privacySection: some View {
        DSSectionCard(
            "Privacy",
            helperText: rememberSession
                ? "Your SID is stored in the iOS Keychain so the app stays signed in across launches."
                : "Saved credentials are removed. You'll need to sign in every time you open the app."
        ) {
            DSSettingsRow.toggle(
                systemImage: "lock.rotation",
                label: "Remember session",
                isOn: Binding(
                    get: { rememberSession },
                    set: { newValue in
                        rememberSession = newValue
                        session.setRememberSession(newValue)
                    }
                )
            )
        }
    }

    private var feedbackSection: some View {
        // Opens GitHub's "New issue" page with the matching template pre-
        // selected. The user needs a GitHub account to actually post — that's
        // handled by github.com, we just deep-link the right form.
        DSSectionCard(
            "Feedback",
            helperText: "Opens GitHub in Safari. A GitHub account is required to post."
        ) {
            DSSettingsRow.link(
                systemImage: "lightbulb",
                label: "Suggest a feature",
                destination: URL(string: "https://github.com/Wenzlik/DropStation/issues/new?template=feature_request.md")!
            )
            rowDivider
            DSSettingsRow.link(
                systemImage: "ladybug",
                label: "Report a bug",
                destination: URL(string: "https://github.com/Wenzlik/DropStation/issues/new?template=bug_report.md")!
            )
        }
    }

    private var aboutSection: some View {
        DSSectionCard(
            "About",
            helperText: "© 2026 Vasek Zmrhal · MIT License"
        ) {
            DSSettingsRow.value(
                systemImage: "app.gift",
                label: "App",
                value: "DropStation"
            )
            rowDivider
            // Tappable Version row: pushes the in-app changelog.
            DSSettingsRow.navigation(
                systemImage: "number",
                label: "Version",
                value: Self.versionString
            ) {
                ChangelogView()
            }
            rowDivider
            DSSettingsRow.link(
                systemImage: "person.circle",
                label: "Made by @Wenzlik",
                destination: URL(string: "https://github.com/Wenzlik")!
            )
            rowDivider
            DSSettingsRow.link(
                systemImage: "chevron.left.forwardslash.chevron.right",
                label: "Source on GitHub",
                destination: URL(string: "https://github.com/Wenzlik/DropStation")!
            )
        }
    }

    // MARK: - Helpers

    /// Hairline between rows, indented to align past the leading
    /// SF Symbol (lg padding + 22 pt icon frame + md gap). Every
    /// row in this view has a leading icon, so a single inset
    /// value reads as consistent.
    private var rowDivider: some View {
        Divider()
            .padding(.leading, DSSpacing.lg + 22 + DSSpacing.md)
    }

    /// Same subtle background gradient as Dashboard / Downloads so
    /// the three primary surfaces share a single visual ground.
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
