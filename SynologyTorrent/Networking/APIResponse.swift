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
}

struct TaskListData: Decodable {
    let total: Int
    let offset: Int
    let tasks: [DownloadTask]
}

struct EmptyData: Decodable {}
