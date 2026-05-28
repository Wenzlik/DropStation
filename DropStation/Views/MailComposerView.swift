import SwiftUI
import MessageUI
import UIKit

/// UIViewControllerRepresentable wrapper around iOS's stock mail
/// composer. Presents a modal pre-filled with our bug-report
/// content; reports the result back to SwiftUI via the
/// `onResult` closure.
///
/// **Always gate the present-side with `MFMailComposeViewController.canSendMail()`**
/// — the composer crashes if presented when no mail account is
/// configured. `BugReportView` checks first and uses
/// `mailtoFallbackURL(...)` when this isn't usable.
struct MailComposerView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onResult: (Result) -> Void

    /// Three-way result so the caller can distinguish a successful
    /// send from a user-initiated cancel (both close the sheet,
    /// only one warrants a confirmation alert).
    enum Result {
        case sent
        case cancelled
        case failed(Error)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No mutable state to push down; the composer is one-shot.
    }

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onResult: (Result) -> Void
        init(onResult: @escaping (Result) -> Void) { self.onResult = onResult }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            if let error {
                onResult(.failed(error))
                return
            }
            switch result {
            case .sent:
                onResult(.sent)
            case .cancelled, .saved:
                // "Saved as draft" still closed without delivering;
                // treat as cancelled so we don't show a "sent"
                // confirmation the user didn't earn.
                onResult(.cancelled)
            case .failed:
                onResult(.failed(NSError(
                    domain: "MailCompose",
                    code: Int(result.rawValue),
                    userInfo: [NSLocalizedDescriptionKey: "Mail composer reported failure."]
                )))
            @unknown default:
                onResult(.cancelled)
            }
        }
    }
}

/// Result of building the `mailto:` fallback URL. `carriedBody`
/// signals whether the URL embeds the full report body or only the
/// subject — when the encoded URL would exceed `maxURLLength` we
/// drop the body to keep the URL parsable by iOS / Mail / Gmail.
/// Caller then relies on the clipboard fallback to deliver the
/// composed report.
struct MailtoFallback {
    let url: URL
    let carriedBody: Bool
}

/// Builds a `mailto:` URL as the fallback when the in-app composer
/// isn't available (no configured mail account, or the user routes
/// mail through a third-party client). Caller hands the URL to
/// `UIApplication.shared.open` — iOS resolves it via the default
/// mail handler (Gmail, Outlook, …) or surfaces the picker.
///
/// Encoding contract — RFC 6068 reserves characters that
/// `URLComponents.queryItems` leaves un-encoded by default (`&`,
/// `=`, `+`, `?`, `#`, `%` are all in `.urlQueryAllowed`). If the
/// user's description contains a `&`, the unencoded ampersand
/// breaks the query at that point and the rest of the body
/// vanishes into bogus parameters. We pre-encode both fields with
/// a stricter character set and assign them via
/// `percentEncodedQueryItems` to prevent double-encoding.
///
/// Length guard — mailto URLs over ~1800 chars are silently
/// truncated by some iOS Mail builds and by Gmail iOS. If the
/// composed URL exceeds the limit we re-build it with subject
/// only, so the user still lands in a pre-addressed compose
/// window. The caller MUST surface a clipboard fallback path so
/// the body still reaches the destination.
///
/// Note on Gmail iOS: even within length limits, Gmail iOS drops
/// `body=` from mailto as an anti-spam heuristic. The clipboard
/// fallback in `BugReportView` is unconditional for that reason —
/// we can't detect Gmail's behavior client-side.
func mailtoFallbackURL(
    recipient: String,
    subject: String,
    body: String,
    maxURLLength: Int = 1800
) -> MailtoFallback? {
    let allowed = CharacterSet.urlQueryAllowed.subtracting(
        CharacterSet(charactersIn: "&=+?#%")
    )
    let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

    var components = URLComponents()
    components.scheme = "mailto"
    components.path = recipient
    components.percentEncodedQueryItems = [
        URLQueryItem(name: "subject", value: encodedSubject),
        URLQueryItem(name: "body", value: encodedBody)
    ]

    if let url = components.url, url.absoluteString.count <= maxURLLength {
        return MailtoFallback(url: url, carriedBody: true)
    }

    // URL too long for safe mailto round-trip — drop body, keep
    // subject. Caller is expected to have copied the body to the
    // clipboard before opening this URL.
    components.percentEncodedQueryItems = [
        URLQueryItem(name: "subject", value: encodedSubject)
    ]
    return components.url.map { MailtoFallback(url: $0, carriedBody: false) }
}
