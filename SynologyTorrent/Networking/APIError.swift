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

// Synology API error codes — partial set covering Download Station + Auth.
// See Synology_Download_Station_Web_API.pdf for the full list.
enum SynologyErrorCode {
    static func message(for code: Int) -> String {
        switch code {
        case 100: return "Unknown error."
        case 101: return "Invalid parameter."
        case 102: return "The requested API does not exist."
        case 103: return "The requested method does not exist."
        case 104: return "The requested version does not support the functionality."
        case 105: return "The logged in session does not have permission."
        case 106: return "Session timeout."
        case 107: return "Session interrupted by duplicate login."
        case 400: return "No such account or incorrect password."
        case 401: return "Account disabled."
        case 402: return "Permission denied."
        case 403: return "2-step verification code required."
        case 404: return "Failed to authenticate 2-step verification code."
        default:  return "Synology API returned error \(code)."
        }
    }
}
