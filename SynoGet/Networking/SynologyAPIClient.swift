import Foundation

/// Async/await client for the Synology Download Station and FileStation Web APIs.
///
/// Endpoints used: `SYNO.API.Auth`, `SYNO.DownloadStation.Task`,
/// `SYNO.FileStation.List`. See Synology's published Download Station and
/// DSM Login Web API guides (linked from the project README) for the wire format.
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

    /// Restore a previously-acquired SID without going through `login`.
    /// Caller is responsible for verifying the session is still valid (e.g. by calling `listTasks`).
    func restoreSession(sid: String) {
        self.sid = sid
    }

    func clearSession() {
        self.sid = nil
    }

    // MARK: - Auth

    struct LoginResult {
        /// The new session id.
        let sid: String
        /// Device id returned when `enableDeviceToken=true` was passed together with a valid OTP.
        /// Save it and pass it back via `deviceID` on future logins to skip OTP entry.
        let deviceID: String?
    }

    /// SYNO.API.Auth login (DownloadStation session, API version 6).
    /// Credentials are sent as POST form data so they do not end up in server access logs.
    ///
    /// Skip-OTP flow:
    ///   * On the first 2FA login, pass `otpCode` and `enableDeviceToken=true` and `deviceName`.
    ///     The response will contain a `did` (device id) — save it.
    ///   * On every subsequent login from this device, pass `deviceID` and `deviceName`. No OTP needed.
    @discardableResult
    func login(
        account: String,
        password: String,
        otpCode: String? = nil,
        enableDeviceToken: Bool = false,
        deviceID: String? = nil,
        deviceName: String? = nil
    ) async throws -> LoginResult {
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
        if let otpCode { params["otp_code"] = otpCode }
        if enableDeviceToken { params["enable_device_token"] = "yes" }
        if let deviceID { params["device_id"] = deviceID }
        if let deviceName { params["device_name"] = deviceName }

        let url = baseURL.appendingPathComponent("/webapi/auth.cgi")
        let response: APIResponse<LoginData> = try await postForm(url: url, params: params)
        try ensureSuccess(response)
        guard let data = response.data else {
            throw APIError.synology(code: -1, message: "Login succeeded but no session id returned.")
        }
        self.sid = data.sid
        return LoginResult(sid: data.sid, deviceID: data.did)
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
    /// `destination` is the path **without** a leading slash, starting with a shared folder
    /// (e.g. "Downloads/Movies"). Pass `nil` to use the server's configured default.
    func createTask(uri: String, destination: String? = nil) async throws {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        let url = baseURL.appendingPathComponent("/webapi/DownloadStation/task.cgi")
        // Version 3+ is required for `uri` (per the Synology Download Station API
        // spec) and version 2+ for `destination`. Sending these with the older
        // version=1 we used previously triggers Synology error 101 "Invalid
        // parameter" on DSM 7 builds.
        var params: [String: String] = [
            "api": "SYNO.DownloadStation.Task",
            "version": "3",
            "method": "create",
            "uri": uri,
            "_sid": sid
        ]
        if let destination, !destination.isEmpty { params["destination"] = destination }
        let response: APIResponse<EmptyData> = try await postForm(url: url, params: params)
        try ensureSuccess(response)
    }

    /// Create a download task from a local .torrent / .nzb file.
    ///
    /// Uses the DSM 7 **DownloadStation2** task endpoint, not the legacy
    /// `task.cgi` one — the documented `SYNO.DownloadStation.Task` create
    /// method just keeps returning 101 Invalid parameter for file uploads on
    /// recent DSM builds, regardless of multipart layout (we tried both
    /// option (a) and option (b) from the spec). The DS2 endpoint at
    /// `/webapi/entry.cgi` is what DSM's own web UI uses, and it accepts:
    ///
    ///   - field `torrent` containing the file's binary data
    ///   - a sidecar `file` field whose value is a JSON list of which fields
    ///     are files (here just `["torrent"]`)
    ///   - `mtime` (epoch milliseconds) and `size` of the upload as strings
    ///
    /// Reference: dvcol/synology-download (`SynologyDownload2Service.createTask`).
    func createTask(fileData: Data, filename: String, destination: String? = nil) async throws {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        // DS2 entry.cgi reads `_sid` from the URL query, not from the multipart
        // body — passing it in the body returns 119 SID not found even when the
        // session is valid for every other endpoint we use.
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/webapi/entry.cgi"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "_sid", value: sid)]
        guard let url = components.url else { throw APIError.invalidURL }

        // DS2 task.create has three required fields beyond the call envelope:
        //   type         — "file" for an uploaded .torrent / .nzb, "url" for a URI
        //   destination  — path string; empty string means "use the default folder"
        //   create_list  — whether to prompt for per-file selection after creation
        let fields: [(String, String)] = [
            ("api", "SYNO.DownloadStation2.Task"),
            ("method", "create"),
            ("version", "2"),
            ("type", "\"file\""),
            ("destination", "\"\(destination ?? "")\""),
            ("create_list", "false"),
            ("mtime", String(Int(Date().timeIntervalSince1970 * 1000))),
            ("size", String(fileData.count)),
            ("file", "[\"torrent\"]")
        ]

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            fields: fields,
            fileFieldName: "torrent",
            filename: filename,
            fileData: fileData
        )

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw APIError.http(http.statusCode)
            }
            let decoded = try JSONDecoder().decode(APIResponse<EmptyData>.self, from: data)
            #if DEBUG
            if !decoded.success, let s = String(data: data, encoding: .utf8) {
                print("[SynoGet] createTask(file) FAILED → request URL: \(url.absoluteString)")
                print("[SynoGet] createTask(file) FAILED → filename: \(filename)")
                print("[SynoGet] createTask(file) FAILED → response: \(s)")
            }
            #endif
            try ensureSuccess(decoded, context: .task)
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decoding(error)
        } catch {
            throw APIError.transport(error)
        }
    }

    /// Get the full detail object for a single task. Pulls down detail, transfer, file
    /// (BT only) and tracker (BT only) fields in one call.
    func getTaskInfo(id: String) async throws -> DownloadTask {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        let url = baseURL.appendingPathComponent("/webapi/DownloadStation/task.cgi")
        let params: [String: String] = [
            "api": "SYNO.DownloadStation.Task",
            "version": "1",
            "method": "getinfo",
            "id": id,
            "additional": "detail,transfer,file,tracker",
            "_sid": sid
        ]
        let response: APIResponse<TaskListData> = try await postForm(url: url, params: params)
        try ensureSuccess(response, context: .task)
        guard let task = response.data?.tasks.first else {
            throw APIError.synology(code: 404, message: "Task not found.")
        }
        return task
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

    // MARK: - File Station (folder picker)

    /// List shared folders the logged-in user can access. Returned paths look like
    /// "/Downloads", "/video" — suitable for direct use as the next `listFolders` argument.
    /// The DownloadStation SID is reused; FileStation does not require a separate login.
    func listShares() async throws -> [FileNode] {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        let url = baseURL.appendingPathComponent("/webapi/entry.cgi")
        let params: [String: String] = [
            "api": "SYNO.FileStation.List",
            "version": "2",
            "method": "list_share",
            "_sid": sid
        ]
        let response: APIResponse<FileStationShareList> = try await postForm(url: url, params: params)
        try ensureSuccess(response, context: .task)
        return response.data?.shares ?? []
    }

    /// List folders inside a path. `path` must start with a shared folder, e.g. "/Downloads".
    /// Only directories are returned (`filetype=dir`).
    func listFolders(in path: String) async throws -> [FileNode] {
        guard let baseURL else { throw APIError.invalidURL }
        guard let sid else { throw APIError.notLoggedIn }

        let url = baseURL.appendingPathComponent("/webapi/entry.cgi")
        let params: [String: String] = [
            "api": "SYNO.FileStation.List",
            "version": "2",
            "method": "list",
            "folder_path": path,
            "filetype": "dir",
            "_sid": sid
        ]
        let response: APIResponse<FileStationFileList> = try await postForm(url: url, params: params)
        try ensureSuccess(response, context: .task)
        return response.data?.files ?? []
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

    /// Build a multipart/form-data body where every `fields` entry becomes a regular
    /// form-data part and the file is appended as the final part (DS2 spec requires
    /// the file part to come last so the upload handler picks it up correctly).
    private func multipartBody(
        boundary: String,
        fields: [(String, String)],
        fileFieldName: String,
        filename: String,
        fileData: Data
    ) -> Data {
        let lineBreak = "\r\n"
        var body = Data()

        for (name, value) in fields {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(value)\(lineBreak)".data(using: .utf8)!)
        }

        // Synology returns 101 Invalid parameter if the filename in Content-Disposition
        // contains non-ASCII characters (e.g. Czech diacritics) or characters that break
        // the header syntax. Sanitize aggressively: RFC 6266's basic `filename=""` is
        // ASCII-only, and the actual torrent task name comes from the .torrent file's
        // bencoded `name` key anyway, not from this header.
        let safeFilename = Self.asciiSafe(filename: filename)
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(safeFilename)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(fileData)
        body.append("\(lineBreak)--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        return body
    }

    private static func asciiSafe(filename: String) -> String {
        let stripped = filename.applyingTransform(.stripDiacritics, reverse: false) ?? filename
        let ascii = String(stripped.unicodeScalars.compactMap { $0.isASCII ? Character($0) : nil })
        // Strip characters that would break the quoted filename in the header.
        let cleaned = ascii.filter { $0 != "\"" && $0 != "\\" && $0 != "\r" && $0 != "\n" }
        return cleaned.isEmpty ? "file.torrent" : cleaned
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
                let decoded = try JSONDecoder().decode(APIResponse<T>.self, from: data)
                #if DEBUG
                // When debugging push-approval flow: log the raw body whenever Synology
                // says the call failed. Synology often tucks extra fields (auth token,
                // approval id, etc.) into the response that don't show up in the
                // documented schema.
                if !decoded.success, let s = String(data: data, encoding: .utf8) {
                    let method = params["method"] ?? "?"
                    let api = params["api"] ?? "?"
                    print("[SynoGet] \(api) method=\(method) FAILED → \(s)")
                }
                #endif
                return decoded
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
            let k = key.addingPercentEncoding(withAllowedCharacters: Self.formAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: Self.formAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    /// RFC 3986 unreserved set (`A-Z a-z 0-9 - . _ ~`). Anything else — including the
    /// form delimiters `&` `=` `+`, but also `,` `/` `:` and the `?` plus `&` chains
    /// inside magnet URIs — gets percent-encoded. The previous `.urlQueryAllowed`
    /// permitted `&` in values, so a magnet link's trailing `&dn=…&tr=…` was passed
    /// through unencoded and the server saw each `&` as a new form parameter
    /// boundary, producing Synology error 101 "Invalid parameter" on createTask.
    private static let formAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
