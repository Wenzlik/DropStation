import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case notLoggedIn
    case http(Int)
    case decoding(Error)
    case synology(code: Int, message: String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL."
        case .notLoggedIn: return "Not logged in."
        case .http(let code): return "HTTP error \(code)."
        case .decoding(let err): return "Decoding error: \(err.localizedDescription)"
        case .synology(let code, let message): return "Synology error \(code): \(message)"
        case .transport(let err): return err.localizedDescription
        }
    }
}

// Synology API error codes. Codes in the 4xx range mean different things depending
// on which API returned them (auth vs Download Station task), so the lookup is
// context-aware. See `Synology_Download_Station_Web_API.pdf` for the full list.
enum SynologyErrorCode {
    enum Context {
        case auth
        case task
    }

    static func message(for code: Int, context: Context = .auth) -> String {
        if let common = commonMessage(for: code) {
            return common
        }
        switch context {
        case .auth: return authMessage(for: code)
        case .task: return taskMessage(for: code)
        }
    }

    /// Codes 100-107 are returned by every endpoint with the same meaning.
    private static func commonMessage(for code: Int) -> String? {
        switch code {
        case 100: return "Unknown error."
        case 101: return "Invalid parameter."
        case 102: return "The requested API does not exist."
        case 103: return "The requested method does not exist."
        case 104: return "The requested version does not support the functionality."
        case 105: return "The logged in session does not have permission."
        case 106: return "Session timeout."
        case 107: return "Session interrupted by duplicate login."
        default:  return nil
        }
    }

    private static func authMessage(for code: Int) -> String {
        switch code {
        case 400: return "No such account or incorrect password."
        case 401: return "Account disabled."
        case 402: return "Permission denied."
        case 403: return "2-step verification code required."
        case 404: return "Failed to authenticate 2-step verification code."
        default:  return "Synology API returned error \(code)."
        }
    }

    private static func taskMessage(for code: Int) -> String {
        switch code {
        case 400: return "File upload failed."
        case 401: return "Maximum number of tasks reached."
        case 402: return "Destination denied."
        case 403: return "Destination does not exist."
        case 404: return "Invalid task ID."
        case 405: return "Invalid task action."
        case 406: return "No default destination configured."
        case 407: return "Set destination failed."
        case 408: return "File does not exist."
        default:  return "Synology API returned error \(code)."
        }
    }
}
