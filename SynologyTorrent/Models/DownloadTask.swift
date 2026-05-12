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
