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

/// Builds a `mailto:` URL as the fallback when the in-app composer
/// isn't available (no configured mail account, or the user
/// disabled Apple Mail entirely). Caller hands the URL to
/// `UIApplication.shared.open` — iOS routes it through whichever
/// mail app the user has set as default (Gmail, Outlook, …) or
/// surfaces the picker.
func mailtoFallbackURL(
    recipient: String,
    subject: String,
    body: String
) -> URL? {
    // RFC 6068 mailto URLs use percent-encoded query parameters. We
    // build via URLComponents rather than string interpolation so
    // the body's newlines and the subject's `[DropStation]` brackets
    // round-trip correctly into Mail.app / Gmail / etc.
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = recipient
    components.queryItems = [
        URLQueryItem(name: "subject", value: subject),
        URLQueryItem(name: "body", value: body)
    ]
    return components.url
}
