import Foundation

/// Modern async/await client for Synology Download Station Web API.
///
/// Reference: `Synology_Download_Station_Web_API.pdf` (in repo root).
/// Original logic ported from keyfun/synology_ds_get (APIManager.swift).
actor SynologyAPIClient {
    private let session: URLSession
    private var baseURL: URL?
    private var sid: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isLoggedIn: Bool { sid != nil }

    func configure(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - Auth

    /// SYNO.API.Auth login (DownloadStation session).
    /// Note: credentials are sent as POST form data (not in URL) to keep them out of server logs.
    func login(account: String, password: String, otpCode: String? = nil) async throws {
        guard let baseURL else { throw APIError.invalidURL }

        var params: [String: String] = [
            "api": "SYNO.API.Auth",
            "version": "6",
            "method": "login",
            "account": account,
            "passwd": password,
            "session": "DownloadStation",
            "format": "sid"
        ]
        if let otpCode {
            params["otp_code"] = otpCode
        }

        let url = baseURL.appendingPathComponent("/webapi/auth.cgi")
        let response: APIResponse<LoginData> = try await postForm(url: url, params: params)

        guard response.success, let sid = response.data?.sid else {
            throw APIError.synology(
                code: response.error?.code ?? -1,
                message: SynologyErrorCode.message(for: response.error?.code ?? -1)
            )
        }
        self.sid = sid
    }

    func logout() async throws {
        guard let baseURL, let sid else { return }
        let url = baseURL.appendingPathComponent("/webapi/auth.cgi")
        let params: [String: String] = [
            "api": "SYNO.API.Auth",
            "version": "1",
            "method": "logout",
            "session": "DownloadStation",
            "_sid": sid
        ]
        _ = try? await postForm(url: url, params: params) as APIResponse<EmptyData>
        self.sid = nil
    }

    // MARK: - Tasks

    func listTasks() async throws -> [DownloadTask] {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        let url = baseURL.appendingPathComponent("/webapi/DownloadStation/task.cgi")
        let params: [String: String] = [
            "api": "SYNO.DownloadStation.Task",
            "version": "1",
            "method": "list",
            "additional": "transfer",
            "_sid": sid
        ]
        let response: APIResponse<TaskListData> = try await postForm(url: url, params: params)
        guard response.success, let data = response.data else {
            throw APIError.synology(
                code: response.error?.code ?? -1,
                message: SynologyErrorCode.message(for: response.error?.code ?? -1)
            )
        }
        return data.tasks
    }

    /// Create a download task from a URI (magnet:, http:, ftp:, https:).
    func createTask(uri: String) async throws {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        let url = baseURL.appendingPathComponent("/webapi/DownloadStation/task.cgi")
        let params: [String: String] = [
            "api": "SYNO.DownloadStation.Task",
            "version": "1",
            "method": "create",
            "uri": uri,
            "_sid": sid
        ]
        let response: APIResponse<EmptyData> = try await postForm(url: url, params: params)
        guard response.success else {
            throw APIError.synology(
                code: response.error?.code ?? -1,
                message: SynologyErrorCode.message(for: response.error?.code ?? -1)
            )
        }
    }

    func deleteTask(id: String) async throws {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        let url = baseURL.appendingPathComponent("/webapi/DownloadStation/task.cgi")
        let params: [String: String] = [
            "api": "SYNO.DownloadStation.Task",
            "version": "1",
            "method": "delete",
            "id": id,
            "force_complete": "false",
            "_sid": sid
        ]
        let response: APIResponse<EmptyData> = try await postForm(url: url, params: params)
        guard response.success else {
            throw APIError.synology(
                code: response.error?.code ?? -1,
                message: SynologyErrorCode.message(for: response.error?.code ?? -1)
            )
        }
    }

    // MARK: - HTTP

    private func postForm<T: Decodable>(url: URL, params: [String: String]) async throws -> APIResponse<T> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = encodeForm(params).data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError.http(http.statusCode)
            }
            do {
                return try JSONDecoder().decode(APIResponse<T>.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    private func encodeForm(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}
