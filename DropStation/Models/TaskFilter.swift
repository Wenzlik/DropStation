import Foundation

/// Groups raw `DownloadTask.Status` values into user-facing categories.
/// `hash_checking`, `filehosting_waiting`, etc. are technical details users
/// shouldn't have to reason about — they all just mean "this is working".
enum TaskFilter: String, CaseIterable, Identifiable {
    case all, downloading, seeding, active, paused, finished, error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .active: return "All active"
        case .paused: return "Paused"
        case .finished: return "Finished"
        case .error: return "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .seeding: return "arrow.up.circle"
        case .active: return "bolt.circle"
        case .paused: return "pause.circle"
        case .finished: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .all:
            return true
        case .downloading:
            // Narrow: only tasks that are actively pulling bytes from somewhere.
            // hash_checking / extracting / filehosting_waiting are part of the
            // download flow too — they precede or extend pulling data.
            switch task.status {
            case .downloading, .waiting, .hash_checking, .filehosting_waiting, .extracting:
                return true
            default:
                return false
            }
        case .seeding:
            return task.status == .seeding
        case .active:
            // Anything the NAS is currently working on, either direction.
            switch task.status {
            case .downloading, .waiting, .hash_checking, .seeding,
                 .filehosting_waiting, .extracting, .finishing:
                return true
            default:
                return false
            }
        case .paused:
            return task.status == .paused
        case .finished:
            return task.status == .finished
        case .error:
            return task.status == .error
        }
    }
}
