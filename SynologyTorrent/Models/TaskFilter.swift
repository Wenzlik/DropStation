import Foundation

/// Groups raw `DownloadTask.Status` values into user-facing categories.
/// `hash_checking`, `filehosting_waiting`, etc. are technical details users
/// shouldn't have to reason about — they all just mean "this is working".
enum TaskFilter: String, CaseIterable, Identifiable {
    case all, active, paused, finished, error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .paused: return "Paused"
        case .finished: return "Finished"
        case .error: return "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .active: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .finished: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            switch task.status {
            case .downloading, .waiting, .hash_checking, .seeding,
                 .filehosting_waiting, .extracting:
                return true
            default:
                return false
            }
        case .paused:
            return task.status == .paused
        case .finished:
            return task.status == .finished || task.status == .finishing
        case .error:
            return task.status == .error
        }
    }
}
