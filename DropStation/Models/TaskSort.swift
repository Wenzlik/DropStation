import Foundation

/// User-selectable sort order for the task list. Persisted via `@AppStorage`
/// (see `TaskSortSettings`) so the choice survives launches.
enum TaskSort: String, CaseIterable, Identifiable {
    case name
    case size
    case dateAdded
    case dateCompleted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name:          return "Name"
        case .size:          return "Size"
        case .dateAdded:     return "Date added"
        case .dateCompleted: return "Date completed"
        }
    }

    var systemImage: String {
        switch self {
        case .name:          return "textformat.abc"
        case .size:          return "internaldrive"
        case .dateAdded:     return "calendar.badge.plus"
        case .dateCompleted: return "calendar.badge.checkmark"
        }
    }
}

enum TaskSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
    var label: String { self == .ascending ? "Ascending" : "Descending" }
    var systemImage: String {
        self == .ascending ? "arrow.up" : "arrow.down"
    }

    var toggled: TaskSortDirection {
        self == .ascending ? .descending : .ascending
    }
}

enum TaskSortSettings {
    static let sortKey = "tasklist.sort"
    static let directionKey = "tasklist.sortDirection"
}

extension Array where Element == DownloadTask {
    /// Sort the array in-place by the chosen criterion and direction. Tasks
    /// missing the comparison value (e.g. no `completed_time` on an unfinished
    /// task) sort consistently at one end via a stable fallback.
    func sorted(by sort: TaskSort, direction: TaskSortDirection) -> [DownloadTask] {
        let asc = direction == .ascending
        switch sort {
        case .name:
            return self.sorted { a, b in
                let cmp = a.title.localizedStandardCompare(b.title)
                return asc ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .size:
            return self.sorted { a, b in
                asc ? a.size.value < b.size.value : a.size.value > b.size.value
            }
        case .dateAdded:
            return self.sorted { a, b in
                let av = a.additional?.detail?.createTime?.value ?? 0
                let bv = b.additional?.detail?.createTime?.value ?? 0
                return asc ? av < bv : av > bv
            }
        case .dateCompleted:
            return self.sorted { a, b in
                let av = a.additional?.detail?.completedTime?.value ?? 0
                let bv = b.additional?.detail?.completedTime?.value ?? 0
                return asc ? av < bv : av > bv
            }
        }
    }
}
