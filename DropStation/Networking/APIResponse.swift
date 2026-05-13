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

struct FileStationShareList: Decodable {
    let shares: [FileNode]
}

struct FileStationFileList: Decodable {
    let files: [FileNode]
}
