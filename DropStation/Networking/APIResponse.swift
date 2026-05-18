import Foundation

struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIErrorPayload?

    struct APIErrorPayload: Decodable {
        let code: Int
    }
}

struct LoginData: Decodable {
    let sid: String
    /// Device id Synology returns when `enable_device_token=yes` is passed on a
    /// 2FA login. We don't request it (the flag suppresses Secure SignIn push)
    /// but keep the field around so the decoder still accepts responses that
    /// happen to include it.
    let did: String?
}

struct TaskListData: Decodable {
    // `total` and `offset` are returned by the list endpoint but not by getinfo
    // (which only returns `tasks`). Optional so both shapes decode cleanly.
    let total: Int?
    let offset: Int?
    let tasks: [DownloadTask]
}

struct EmptyData: Decodable {}

/// Payload of `SYNO.API.Info.query` — DSM returns a top-level JSON
/// object where each key is an API name (`SYNO.DownloadStation.Task`)
/// and the value describes the endpoint (CGI path, min/max version).
/// Decoded into a `[String: APIInfoEntry]` for ergonomics.
struct APIInfoEntry: Decodable {
    let path: String
    let minVersion: Int
    let maxVersion: Int

    enum CodingKeys: String, CodingKey {
        case path
        case minVersion = "minVersion"
        case maxVersion = "maxVersion"
    }
}

struct APIInfoData: Decodable {
    let entries: [String: APIInfoEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.entries = try container.decode([String: APIInfoEntry].self)
    }
}

struct FileStationShareList: Decodable {
    let shares: [FileNode]
}

struct FileStationFileList: Decodable {
    let files: [FileNode]
}
