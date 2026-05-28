import SwiftUI
import MessageUI
import UIKit

/// In-app bug report form. Replaces the old "Report a bug → GitHub
/// new-issue page" link in Settings: a fresh install on a device
/// without a GitHub account couldn't actually file an issue, and
/// asking users to round-trip through Safari to type out
/// reproduction steps was the wrong shape for a complaint flow.
///
/// Transport:
///   1. Prefer `MFMailComposeViewController` so the user reviews
///      the composed message inside our sheet, can edit it, and
///      sends from their own account.
///   2. Fall back to a `mailto:` URL routed through
///      `UIApplication.shared.open`. Triggers iOS's "open in
///      Mail / Gmail / …" picker on devices where the in-app
///      composer is disabled.
///   3. If neither works (no mail clients at all), surface an
///      alert telling the user to write to
///      `BugReport.recipientEmail` directly.
///
/// No SMTP, no embedded credentials, no backend. The data layer
/// (`BugReport`) is shaped so a future HTTPS-endpoint variant can
/// swap in here without restructuring the form.
struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    // Form state
    @State private var subject: String = ""
    @State private var description: String = ""
    @State private var stepsToReproduce: String = ""
    @State private var expectedBehavior: String = ""
    @State private var contactEmail: String = ""
    @State private var includeDiagnostics: Bool = true

    // Transport state
    @State private var preparedSubject: String = ""
    @State private var preparedBody: String = ""
    @State private var showingComposer = false
    @State private var alertContent: AlertContent?

    private struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let dismissesView: Bool
    }

    /// Send is enabled only when both required fields hold non-
    /// whitespace content. The button's `disabled` binding mirrors
    /// this so the user gets the visual cue rather than a no-op
    /// tap.
    private var canSend: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    requiredSection
                    detailsSection
                    contactSection
                    diagnosticsSection
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.lg)
            }
        }
        .navigationTitle("Report a bug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Send") { startSend() }
                    .disabled(!canSend)
            }
        }
        .sheet(isPresented: $showingComposer) {
            MailComposerView(
                recipient: BugReport.recipientEmail,
                subject: preparedSubject,
                body: preparedBody
            ) { result in
                showingComposer = false
                switch result {
                case .sent:
                    alertContent = AlertContent(
                        title: "Thanks",
                        message: "Your report was sent.",
                        dismissesView: true
                    )
                case .cancelled:
                    // User backed out of the composer — keep the
                    // form open with their input intact so they can
                    // try again, no alert needed.
                    break
                case .failed(let error):
                    alertContent = AlertContent(
                        title: "Couldn't send",
                        message: error.localizedDescription,
                        dismissesView: false
                    )
                }
            }
        }
        .alert(item: $alertContent) { content in
            Alert(
                title: Text(content.title),
                message: Text(content.message),
                dismissButton: .default(Text("OK")) {
                    if content.dismissesView { dismiss() }
                }
            )
        }
    }

    // MARK: - Sections

    private var requiredSection: some View {
        DSSectionCard(
            "Report",
            helperText: "Subject and a short description help me triage quickly."
        ) {
            BugReportField(label: "Subject", text: $subject, placeholder: "Short summary")
            rowDivider
            BugReportEditor(
                label: "Description",
                text: $description,
                placeholder: "What happened?",
                minHeight: 100
            )
        }
    }

    private var detailsSection: some View {
        DSSectionCard("Details (optional)") {
            BugReportEditor(
                label: "Steps to reproduce",
                text: $stepsToReproduce,
                placeholder: "1. …\n2. …",
                minHeight: 80
            )
            rowDivider
            BugReportEditor(
                label: "Expected behavior",
                text: $expectedBehavior,
                placeholder: "What should have happened?",
                minHeight: 60
            )
        }
    }

    private var contactSection: some View {
        DSSectionCard(
            "Contact (optional)",
            helperText: "I may reply if I need more detail."
        ) {
            BugReportField(
                label: "Email",
                text: $contactEmail,
                placeholder: "you@example.com",
                keyboard: .emailAddress,
                autocap: .never
            )
        }
    }

    private var diagnosticsSection: some View {
        DSSectionCard(
            "Diagnostics",
            helperText: includeDiagnostics
                ? "Attaches app/iOS version, device model, hostname, auth method, session state, and timestamp. No passwords, SID, cookies, OTP, or torrent names."
                : "Diagnostics block won't be attached."
        ) {
            DSSettingsRow.toggle(
                systemImage: "info.circle",
                label: "Include diagnostics",
                isOn: $includeDiagnostics
            )
        }
    }

    /// Hairline between rows inside a section card. Indented to
    /// align with the section card's internal padding so the
    /// divider doesn't visually clip into the card edge.
    private var rowDivider: some View {
        Divider().padding(.leading, DSSpacing.lg)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Actions

    /// Composes a `BugReport` from the form state and routes it
    /// through the best-available mail transport. The Mail-app
    /// canSendMail() check is per-app — when the in-app composer
    /// is disabled we still try the mailto: URL because the user
    /// may have a third-party mail client set as default.
    ///
    /// On the mailto fallback path we unconditionally copy the
    /// composed report to the clipboard before opening the URL.
    /// Some mail clients (notably Gmail iOS) silently drop `body=`
    /// from mailto URLs as anti-spam — there's no way to detect
    /// that client-side, so we always give the user a paste-able
    /// backup and tell them in the confirmation alert.
    private func startSend() {
        let report = makeReport()
        preparedSubject = report.emailSubjectLine
        preparedBody = report.composeEmailBody()

        if MFMailComposeViewController.canSendMail() {
            showingComposer = true
            return
        }

        // Fallback transport — copy first, then open the mailto URL.
        // Order matters: if `open` immediately backgrounds us, the
        // clipboard write still happened.
        UIPasteboard.general.string = clipboardPayload(
            subject: preparedSubject,
            body: preparedBody
        )

        guard let fallback = mailtoFallbackURL(
            recipient: BugReport.recipientEmail,
            subject: preparedSubject,
            body: preparedBody
        ) else {
            presentNoMailAlert(clipboardReady: true)
            return
        }

        UIApplication.shared.open(fallback.url) { opened in
            if opened {
                alertContent = AlertContent(
                    title: "Opened in your mail app",
                    message: fallback.carriedBody
                        ? "If the subject or body looks empty, paste from your clipboard — the full report is already copied."
                        : "Your report was too long to pre-fill. Paste it from your clipboard into the email body.",
                    dismissesView: true
                )
            } else {
                presentNoMailAlert(clipboardReady: true)
            }
        }
    }

    /// Plain-text dump that the user pastes into their mail client
    /// when the mailto body is dropped or truncated. Prefixed with
    /// `Subject:` so the leading line is still useful even if the
    /// user pastes into an already-populated compose window.
    private func clipboardPayload(subject: String, body: String) -> String {
        "Subject: \(subject)\n\n\(body)"
    }

    private func presentNoMailAlert(clipboardReady: Bool = false) {
        let message: String
        if clipboardReady {
            message = "The report is on your clipboard. Email \(BugReport.recipientEmail) and paste it as the message."
        } else {
            message = "Please email \(BugReport.recipientEmail) directly."
        }
        alertContent = AlertContent(
            title: "No mail app available",
            message: message,
            dismissesView: false
        )
    }

    private func makeReport() -> BugReport {
        let diagnostics: Diagnostics? = includeDiagnostics
            ? Diagnostics.capture(
                hostname: session.config.host.isEmpty ? nil : session.config.host,
                authMethod: AuthMethodSettings.effective.label,
                sessionState: Self.sessionStateLabel(session.state)
            )
            : nil
        return BugReport(
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            stepsToReproduce: stepsToReproduce.trimmedNonEmpty,
            expectedBehavior: expectedBehavior.trimmedNonEmpty,
            contactEmail: contactEmail.trimmedNonEmpty,
            includeDiagnostics: includeDiagnostics,
            diagnostics: diagnostics
        )
    }

    /// Stable user-facing label for the session machine. Decoupled
    /// from the raw enum case name so a future enum reshuffle
    /// doesn't leak into the diagnostics payload format that
    /// triagers parse by eye. Strips out the associated reason on
    /// `.sessionUnauthorized` / `.error` for privacy — the reason
    /// can contain server-supplied strings we don't want to ship
    /// uncontrolled.
    private static func sessionStateLabel(_ state: SessionStore.State) -> String {
        switch state {
        case .restoring:             return "restoring"
        case .loggedOut:             return "loggedOut"
        case .authenticating:        return "authenticating"
        case .twoFactorRequired:     return "twoFactorRequired"
        case .validatingApiAccess:   return "validatingApiAccess"
        case .loggedIn:              return "loggedIn"
        case .sessionUnauthorized:   return "sessionUnauthorized"
        case .connectionLost:        return "connectionLost"
        case .error:                 return "error"
        }
    }
}

private extension String {
    /// `nil` when the string is empty after trimming whitespace,
    /// the trimmed string otherwise. Used for optional bug-report
    /// fields so the composed email doesn't carry empty section
    /// headings for fields the user left blank.
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Small form helpers
//
// Kept private to this file rather than promoted into the
// DesignSystem — these are one-off shapes for the bug-report form.
// If a second settings-style form lands (feedback, account edit,
// …) fold them back into DSLabeledTextField / DSLabeledTextEditor
// at that point. Premature DS extraction would force every
// labeled-text site to share a shape that hasn't been validated by
// a second use yet.

private struct BugReportField: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var placeholder: LocalizedStringKey = ""
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
    }
}

private struct BugReportEditor: View {
    let label: LocalizedStringKey
    @Binding var text: String
    var placeholder: LocalizedStringKey = ""
    var minHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            // TextEditor has no native placeholder; overlay a
            // ghost label that disappears once the binding is
            // non-empty. The .allowsHitTesting(false) keeps the
            // overlay from intercepting taps that should focus
            // the editor.
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
    }
}
