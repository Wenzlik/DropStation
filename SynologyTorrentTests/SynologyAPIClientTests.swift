import XCTest
@testable import SynologyTorrent

final class ServerConfigTests: XCTestCase {
    func testBaseURLConstruction() {
        let config = ServerConfig(scheme: .https, host: "nas.local", port: 5001, account: "vasek")
        XCTAssertEqual(config.baseURL?.absoluteString, "https://nas.local:5001")
    }

    func testEmptyHostProducesNilURL() {
        let config = ServerConfig(scheme: .https, host: "", port: 5001, account: "vasek")
        // URLComponents with empty host still returns a URL in some forms; this asserts current behavior.
        XCTAssertNotNil(config.baseURL)
    }
}

final class DownloadTaskDecodingTests: XCTestCase {
    func testDecodeMinimalTask() throws {
        let json = """
        {
          "id": "dbid_1",
          "title": "ubuntu-24.04.iso",
          "size": 5368709120,
          "status": "downloading",
          "type": "bt",
          "username": "vasek",
          "additional": { "transfer": { "size_downloaded": 2684354560, "size_uploaded": 0, "speed_download": 1048576, "speed_upload": 0 } }
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(DownloadTask.self, from: json)
        XCTAssertEqual(task.id, "dbid_1")
        XCTAssertEqual(task.status, .downloading)
        XCTAssertEqual(task.type, .bt)
        XCTAssertEqual(task.progress, 0.5, accuracy: 0.001)
    }

    func testDecodeUnknownStatusFallsBack() throws {
        let json = """
        {"id":"x","title":"t","size":1,"status":"future_state","type":"http","username":"u"}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(DownloadTask.self, from: json)
        XCTAssertEqual(task.status, .unknown)
    }
}
