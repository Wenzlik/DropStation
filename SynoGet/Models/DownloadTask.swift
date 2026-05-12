import Foundation

struct DownloadTask: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let size: Int64
    let status: Status
    let type: TaskType
    let username: String
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

        struct Transfer: Codable, Hashable {
            let sizeDownloaded: Int64
            let sizeUploaded: Int64
            let speedDownload: Int64
            let speedUpload: Int64

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
            let createTime: String?
            let priority: String?
            let connectedSeeders: Int?
            let connectedLeechers: Int?
            let totalPeers: Int?

            enum CodingKeys: String, CodingKey {
                case destination, uri, priority
                case createTime = "create_time"
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
            // Synology returns sizes as either Int or String (numeric strings for very
            // large files). FlexibleInt64 accepts both.
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
            let updateTimer: Int?
            let seeds: Int?
            let peers: Int?

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
        guard size > 0, let downloaded = additional?.transfer?.sizeDownloaded else { return 0 }
        return min(1.0, Double(downloaded) / Double(size))
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
        case .paused, .error:
            return true
        default:
            return false
        }
    }
}

/// Decodes an integer that may arrive as either a JSON number or a JSON string
/// (Synology's API sometimes returns large integers as strings, e.g. file sizes).
struct FlexibleInt64: Codable, Hashable {
    let value: Int64

    init(_ value: Int64) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Int64.self) {
            value = n
        } else if let s = try? container.decode(String.self), let n = Int64(s) {
            value = n
        } else {
            value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
