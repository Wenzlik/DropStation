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
    /// Returned only when `enable_device_token=yes` was passed on a login that
    /// completed an OTP challenge. Save and reuse to skip OTP next time.
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

struct FileStationShareList: Decodable {
    let shares: [FileNode]
}

struct FileStationFileList: Decodable {
    let files: [FileNode]
}
