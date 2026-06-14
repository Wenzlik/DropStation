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
    @AppStorage(PasswordPersistenceSettings.storageKey) private var rememberPassword: Bool = true
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
                        if isSignedIn { accountHero }
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

    // MARK: Account hero

    /// Identity card at the top of Settings — the one `.primary`
    /// glass surface on this screen. Mirrors the dashboard's hero
    /// pattern: avatar + name + ambient status line + actions
    /// inline inside the card rather than as separate list rows.
    /// Helper text sits below the card per the Phase-3 section
    /// shape.
    private var accountHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSCard(.primary) {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    accountHeroIdentity
                    Divider()
                    accountHeroActions
                }
            }
            Text("Sign out clears the saved session. Forget this device additionally removes any legacy credentials older builds may have stored.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.sm)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Avatar + account label + ambient status line. The status
    /// line composes through DSMetricRow so the dot/text rhythm
    /// matches the dashboard hero header pixel-for-pixel.
    private var accountHeroIdentity: some View {
        HStack(spacing: DSSpacing.md) {
            DSAvatarCircle(
                account: session.config.account.isEmpty
                    ? "DS"
                    : session.config.account,
                size: 52
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(session.config.account.isEmpty
                     ? "DropStation"
                     : session.config.account)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    DSStatusDot(tint: .green)
                    DSMetricRow(values: accountHeroMetrics, font: .caption)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "Online · nas.local · 0.4.0 (8)" — host is dropped if the
    /// config is empty (defensive; shouldn't happen post-login
    /// but matches the earlier defence). Version is always
    /// surfaced for at-a-glance debug context.
    private var accountHeroMetrics: [String] {
        var values: [String] = ["Online"]
        if !session.config.host.isEmpty {
            values.append(session.config.host)
        }
        values.append(Self.versionString)
        return values
    }

    /// Sign out as the visible bordered action; Forget this
    /// device kept inline but rendered as a quiet text-only
    /// destructive button at `.caption.weight(.medium)`. Both
    /// stay reachable in a single tap — no overflow menu — but
    /// the destructive variant no longer competes visually with
    /// Sign out's bordered chrome.
    private var accountHeroActions: some View {
        HStack(spacing: DSSpacing.md) {
            Button {
                Task {
                    await session.logout()
                    dismiss()
                }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                confirmForget = true
            } label: {
                Text("Forget this device")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
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
            helperText: privacyHelperText
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
            rowDivider
            DSSettingsRow.toggle(
                systemImage: "key",
                label: "Remember password",
                isOn: Binding(
                    get: { rememberPassword },
                    set: { newValue in
                        rememberPassword = newValue
                        session.setRememberPassword(newValue)
                    }
                )
            )
        }
    }

    /// Helper copy under the Privacy card. Spells out the OTP-only
    /// recovery flow when "Remember password" is on, since that's the
    /// behaviour most users are looking for.
    private var privacyHelperText: LocalizedStringKey {
        switch (rememberSession, rememberPassword) {
        case (_, true):
            return "Your session and password are stored in the iOS Keychain. When the session expires you'll only be asked for your verification code, not your password."
        case (true, false):
            return "Your session is stored in the iOS Keychain so the app stays signed in across launches. Your password is not saved."
        case (false, false):
            return "Nothing is saved. You'll sign in with your password and verification code every time you open the app."
        }
    }

    private var feedbackSection: some View {
        // Suggest a feature stays on GitHub: feature requests are
        // discussions that benefit from being public — anyone can
        // upvote, comment, propose alternatives — and a GitHub
        // account is the right friction filter for that surface.
        //
        // Report a bug moves in-app: bug reports want low friction
        // (the user is already frustrated) and benefit from
        // structured fields (subject / steps / expected) plus
        // optional diagnostics, neither of which a free-form
        // GitHub issue does well.
        DSSectionCard(
            "Feedback",
            helperText: "Bug reports send via your mail app. Feature requests open on GitHub."
        ) {
            DSSettingsRow.link(
                systemImage: "lightbulb",
                label: "Suggest a feature",
                destination: URL(string: "https://github.com/Wenzlik/DropStation/issues/new?template=feature_request.md")!
            )
            rowDivider
            DSSettingsRow.navigation(
                systemImage: "ladybug",
                label: "Report a bug"
            ) {
                BugReportView()
            }
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
