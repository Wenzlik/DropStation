import Foundation
import SwiftUI

struct DownloadTask: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    /// Total task size in bytes. Synology returns this as either a JSON number or a
    /// quoted numeric string depending on DSM version and task size, hence FlexibleInt64.
    let size: FlexibleInt64
    let status: Status
    let type: TaskType
    let username: String?
    let additional: Additional?

    enum Status: String, Codable {
        case waiting, downloading, paused, finishing, finished, hash_checking, seeding
        case filehosting_waiting, extracting, error
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    enum TaskType: String, Codable {
        case bt, nzb, http, ftp, emule, https, magnet
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
            self = TaskType(rawValue: raw) ?? .unknown
        }
    }

    struct Additional: Codable, Hashable {
        let transfer: Transfer?
        let detail: Detail?
        let file: [TorrentFile]?
        let tracker: [Tracker]?

        // Every numeric field below uses FlexibleInt64 (or its optional variant) because
        // Synology is inconsistent about returning numbers as JSON numbers vs quoted
        // strings — and individual DSM versions differ. Optional where the field can be
        // genuinely absent (BT-only counters on an HTTP task, etc.).
        struct Transfer: Codable, Hashable {
            let sizeDownloaded: FlexibleInt64
            let sizeUploaded: FlexibleInt64
            let speedDownload: FlexibleInt64
            let speedUpload: FlexibleInt64

            enum CodingKeys: String, CodingKey {
                case sizeDownloaded = "size_downloaded"
                case sizeUploaded = "size_uploaded"
                case speedDownload = "speed_download"
                case speedUpload = "speed_upload"
            }
        }

        struct Detail: Codable, Hashable {
            let destination: String?
            let uri: String?
            /// Unix timestamp. Spec says "string" but real DSM returns it as a number.
            let createTime: FlexibleInt64?
            /// Unix timestamp when the task transitioned to `finished`. Absent
            /// or 0 for tasks that haven't completed yet. Used by sort-by-date-
            /// completed in the list.
            let completedTime: FlexibleInt64?
            let priority: String?
            let connectedSeeders: FlexibleInt64?
            let connectedLeechers: FlexibleInt64?
            let totalPeers: FlexibleInt64?

            enum CodingKeys: String, CodingKey {
                case destination, uri, priority
                case createTime = "create_time"
                case completedTime = "completed_time"
                case connectedSeeders = "connected_seeders"
                case connectedLeechers = "connected_leechers"
                case totalPeers = "total_peers"
            }
        }

        struct TorrentFile: Codable, Hashable, Identifiable {
            // All fields optional — Synology occasionally returns sparse entries (e.g.
            // padding files in torrents have no filename, deselected files have no
            // sizeDownloaded). Non-optional fields here would fail the whole detail
            // request rather than just dropping the empty entry.
            let filename: String?
            let size: FlexibleInt64?
            let sizeDownloaded: FlexibleInt64?
            let priority: String?

            enum CodingKeys: String, CodingKey {
                case filename, priority
                case size
                case sizeDownloaded = "size_downloaded"
            }

            var id: String { filename ?? UUID().uuidString }
            var progress: Double {
                guard let s = size?.value, s > 0, let d = sizeDownloaded?.value else { return 0 }
                return min(1.0, Double(d) / Double(s))
            }
        }

        struct Tracker: Codable, Hashable, Identifiable {
            // url is sometimes absent or null (DHT pseudo-trackers, removed entries).
            let url: String?
            let status: String?
            let updateTimer: FlexibleInt64?
            let seeds: FlexibleInt64?
            let peers: FlexibleInt64?

            enum CodingKeys: String, CodingKey {
                case url, status, seeds, peers
                case updateTimer = "update_timer"
            }

            // Stable identity only for trackers with a URL; URL-less entries are filtered
            // out before display so the placeholder id never reaches a ForEach.
            var id: String { url ?? "" }
        }
    }

    var progress: Double {
        let total = size.value
        guard total > 0, let downloaded = additional?.transfer?.sizeDownloaded.value else { return 0 }
        return min(1.0, Double(downloaded) / Double(total))
    }

    /// True when the task has fully downloaded its payload. Used to fold the
    /// various "done" representations together — Synology returns `paused`
    /// for BT tasks stopped after they completed (DS2 Task.Complete makes a
    /// seeding task look paused, not finished), so we lean on the size
    /// comparison to recognise an effectively-finished row.
    var isAtCompletion: Bool {
        let total = size.value
        guard total > 0,
              let downloaded = additional?.transfer?.sizeDownloaded.value
        else { return false }
        return downloaded >= total
    }

    /// Combined display label for the status pill. Folds paused-at-100 % and
    /// `.finished` into a single user-facing "Ended" — matching how DSM web
    /// labels these — so users aren't confused by Stop landing them in a
    /// "Paused" label that sounds temporary.
    var displayStatusLabel: String {
        if isAtCompletion, status == .paused { return "Ended" }
        if status == .finished { return "Ended" }
        return status.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Tint shown by the StatusPill. Matches displayStatusLabel by collapsing
    /// the "ended" states onto the finished colour (grey).
    var displayStatusTintRaw: DownloadTask.Status {
        if isAtCompletion, status == .paused { return .finished }
        return status
    }

    var canPause: Bool {
        switch status {
        case .downloading, .waiting, .seeding, .hash_checking, .filehosting_waiting:
            return true
        default:
            return false
        }
    }

    var canResume: Bool {
        switch status {
        case .paused, .error, .finished:
            // `.finished` is in here so Stop is reversible: after stopping
            // a BT task its status is `finished`, and a Resume puts it
            // back into seeding. For non-BT types Resume on finished is
            // a server-side no-op, which is fine.
            return true
        default:
            return false
        }
    }

    /// Whether the Stop action makes sense: DS2 Task.Complete only finalizes
    /// tasks that are already 100 % (seeding or finishing — typical BT
    /// after-download states). Stopping a still-downloading task just pauses
    /// it without actually transitioning to `finished`, which is confusing
    /// UX, so we hide the affordance there. DSM web does the same — its
    /// "End" button only appears on seeding rows.
    var canStop: Bool {
        switch status {
        case .seeding, .finishing:
            return true
        default:
            return false
        }
    }
}

extension DownloadTask.Status {
    /// Accent colour used by the status pill and progress bar.
    var tintColor: Color {
        switch self {
        case .downloading, .seeding, .extracting: return .green
        case .waiting, .hash_checking, .filehosting_waiting, .finishing: return .blue
        case .paused: return .orange
        case .finished: return .gray
        case .error: return .red
        case .unknown: return .gray
        }
    }
}

extension DownloadTask.TaskType {
    /// Small SF Symbol shown left of the task title.
    var systemImage: String {
        switch self {
        case .bt, .magnet: return "arrow.triangle.2.circlepath"
        case .http, .https: return "globe"
        case .ftp: return "server.rack"
        case .nzb: return "newspaper"
        case .emule: return "person.2"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Decodes an integer that may arrive as either a JSON number or a JSON string
/// (Synology's API is inconsistent — file sizes are spec'd as strings, peer counts
/// as ints, but actual DSM behavior swaps these around per version).
///
/// Conforms to ExpressibleByIntegerLiteral so test fixtures can still write
/// `DownloadTask(..., size: 1, ...)` instead of `FlexibleInt64(1)`.
struct FlexibleInt64: Codable, Hashable, ExpressibleByIntegerLiteral {
    let value: Int64

    init(_ value: Int64) { self.value = value }
    init(integerLiteral value: Int64) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Int64.self) {
            value = n
        } else if let s = try? container.decode(String.self), let n = Int64(s) {
            value = n
        } else if let d = try? container.decode(Double.self) {
            // Some endpoints return floats for averages — coerce to int.
            value = Int64(d)
        } else {
            value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
