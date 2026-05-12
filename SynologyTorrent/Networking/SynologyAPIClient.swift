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
        try ensureSuccess(response)
        guard let sid = response.data?.sid else {
            throw APIError.synology(code: -1, message: "Login succeeded but no session id returned.")
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
        try ensureSuccess(response, context: .task)
        return response.data?.tasks ?? []
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
        try ensureSuccess(response)
    }

    /// Create a download task from a local .torrent / .nzb file.
    ///
    /// Per the Synology API spec ("Limitations" on the Create endpoint), when uploading a
    /// file the upload part must be the **last** field in the multipart body.
    func createTask(fileData: Data, filename: String) async throws {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        // Non-file params are sent as URL query so they cannot be misordered relative
        // to the file part (option (a) in the spec's Limitations section).
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/webapi/DownloadStation/task.cgi"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "api", value: "SYNO.DownloadStation.Task"),
            URLQueryItem(name: "version", value: "1"),
            URLQueryItem(name: "method", value: "create"),
            URLQueryItem(name: "_sid", value: sid)
        ]
        guard let url = components.url else { throw APIError.invalidURL }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, filename: filename, fileData: fileData)

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError.http(http.statusCode)
            }
            let decoded = try JSONDecoder().decode(APIResponse<EmptyData>.self, from: data)
            try ensureSuccess(decoded, context: .task)
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decoding(error)
        } catch {
            throw APIError.transport(error)
        }
    }

    func pauseTasks(ids: [String]) async throws {
        try await taskAction(method: "pause", ids: ids)
    }

    func resumeTasks(ids: [String]) async throws {
        try await taskAction(method: "resume", ids: ids)
    }

    private func taskAction(method: String, ids: [String]) async throws {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }
        guard !ids.isEmpty else { return }

        let url = baseURL.appendingPathComponent("/webapi/DownloadStation/task.cgi")
        let params: [String: String] = [
            "api": "SYNO.DownloadStation.Task",
            "version": "1",
            "method": method,
            "id": ids.joined(separator: ","),
            "_sid": sid
        ]
        let response: APIResponse<EmptyData> = try await postForm(url: url, params: params)
        try ensureSuccess(response, context: .task)
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
        try ensureSuccess(response, context: .task)
    }

    // MARK: - HTTP

    private func ensureSuccess<T>(_ response: APIResponse<T>, context: SynologyErrorCode.Context = .auth) throws {
        guard !response.success else { return }
        let code = response.error?.code ?? -1
        throw APIError.synology(code: code, message: SynologyErrorCode.message(for: code, context: context))
    }

    private func multipartBody(boundary: String, filename: String, fileData: Data) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(fileData)
        body.append("\(lineBreak)--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        return body
    }

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
