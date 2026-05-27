import Foundation
import UIKit

/// Plain-data shape for an in-app bug report. The view (`BugReportView`)
/// fills this in; the transport step (`MailComposerView` today, an
/// HTTPS endpoint in some future build) reads it.
///
/// Why the split: the spec calls out that the v1 transport must be a
/// system mail composer (no SMTP credentials in the app, no backend),
/// but anticipates a future move to `App → HTTPS endpoint → email
/// provider` once we run a small server-side forwarder. Carrying the
/// composed report as plain data means that future swap only touches
/// the send step — the form, the diagnostics rules, and the body
/// formatting stay put.
struct BugReport {
    var subject: String
    var description: String
    var stepsToReproduce: String?
    var expectedBehavior: String?
    var contactEmail: String?
    var includeDiagnostics: Bool
    var diagnostics: Diagnostics?

    /// Recipient for the v1 Mail-composer transport. Carved out as a
    /// constant so a future HTTPS-endpoint variant can target a
    /// different address (or none, if it's a server-side route) without
    /// re-threading the value through the view layer.
    static let recipientEmail = "dropstation@zmrhal.cz"
}

/// Optional-by-design diagnostics block. The user opts in via a toggle
/// in `BugReportView`; when off, none of this is captured or attached
/// to the email body.
///
/// Privacy contract — captured fields:
///   - app version + build
///   - iOS version
///   - device model identifier (e.g. "iPhone15,2")
///   - hostname only (no scheme/port/account — `host` is the bare
///     domain or IP the user typed)
///   - auth method label ("Verification code" / "Secure SignIn app")
///   - session state label
///   - capture timestamp
///
/// Explicitly **never** captured:
///   - passwords
///   - SID / session cookies
///   - OTP codes
///   - private tokens of any kind
///   - any portion of the task list (torrent names, magnet URIs)
///   - logs that could carry the above
///
/// The capture entry points take only the safe scalars as arguments
/// (hostname, auth method label, session state label) — they do not
/// receive the live `SessionStore` or `ServerConfig` and so can't be
/// accidentally widened to leak secrets later.
struct Diagnostics {
    let appVersion: String
    let appBuild: String
    let iOSVersion: String
    let deviceModel: String
    let hostname: String?
    let authMethod: String?
    let sessionState: String?
    let timestamp: Date

    static func capture(
        hostname: String?,
        authMethod: String?,
        sessionState: String?,
        now: Date = Date()
    ) -> Diagnostics {
        let info = Bundle.main.infoDictionary
        return Diagnostics(
            appVersion: (info?["CFBundleShortVersionString"] as? String) ?? "?",
            appBuild: (info?["CFBundleVersion"] as? String) ?? "?",
            iOSVersion: UIDevice.current.systemVersion,
            deviceModel: Self.deviceModelIdentifier(),
            hostname: hostname,
            authMethod: authMethod,
            sessionState: sessionState,
            timestamp: now
        )
    }

    /// "iPhone15,2"-style machine identifier rather than the generic
    /// "iPhone" / "iPad" UIDevice returns. Reads `utsname.machine`
    /// directly — accurate enough to map to a real device tier and
    /// stable across iOS versions, no private API. Returns an empty
    /// string on the (theoretical) zero-init failure path; the email
    /// body renders that as an empty field rather than failing.
    private static func deviceModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        // Capture the byte count into a local first — passing
        // `MemoryLayout.size(ofValue: info.machine)` inside the
        // `withUnsafePointer(to: &info.machine)` closure trips
        // Swift's exclusive-access rule (one read + one inout on
        // the same property at the same time).
        let machineSize = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { ptr -> String in
            ptr.withMemoryRebound(to: CChar.self, capacity: machineSize) {
                String(cString: $0)
            }
        }
    }
}

extension BugReport {
    /// Plain-text email body. Sections render only when populated, so
    /// blank-optional fields don't leave empty headings behind. The
    /// ordering matches the order the user filled the form, so a
    /// triager can scan a report top-to-bottom without scrolling
    /// around past empty placeholders.
    func composeEmailBody() -> String {
        var lines: [String] = []
        lines.append(description)
        lines.append("")
        if let steps = stepsToReproduce, !steps.isEmpty {
            lines.append("Steps to reproduce")
            lines.append("-------------------")
            lines.append(steps)
            lines.append("")
        }
        if let expected = expectedBehavior, !expected.isEmpty {
            lines.append("Expected behavior")
            lines.append("-----------------")
            lines.append(expected)
            lines.append("")
        }
        if let contact = contactEmail, !contact.isEmpty {
            lines.append("Contact: \(contact)")
            lines.append("")
        }
        if includeDiagnostics, let d = diagnostics {
            lines.append("Diagnostics")
            lines.append("-----------")
            lines.append("App version: \(d.appVersion) (\(d.appBuild))")
            lines.append("iOS: \(d.iOSVersion)")
            lines.append("Device: \(d.deviceModel)")
            if let h = d.hostname { lines.append("Host: \(h)") }
            if let a = d.authMethod { lines.append("Auth method: \(a)") }
            if let s = d.sessionState { lines.append("Session state: \(s)") }
            lines.append("Captured at: \(ISO8601DateFormatter().string(from: d.timestamp))")
        }
        return lines.joined(separator: "\n")
    }

    /// Subject line as it appears on the composed email. Prefixed so
    /// inbox triage can filter on `[DropStation]` without searching
    /// the body.
    var emailSubjectLine: String {
        "[DropStation] \(subject)"
    }
}
