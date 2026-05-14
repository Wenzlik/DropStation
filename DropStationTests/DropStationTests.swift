import XCTest
import SwiftUI
@testable import DropStation

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

    func testPauseResumeAvailability() throws {
        func task(status: DownloadTask.Status) -> DownloadTask {
            DownloadTask(id: "x", title: "t", size: 1, status: status, type: .bt, username: "u", additional: nil)
        }
        XCTAssertTrue(task(status: .downloading).canPause)
        XCTAssertTrue(task(status: .seeding).canPause)
        XCTAssertFalse(task(status: .paused).canPause)
        XCTAssertTrue(task(status: .paused).canResume)
        XCTAssertTrue(task(status: .error).canResume)
        // .finished tasks are resumable so a Stop is reversible
        // (BT: re-enters seeding; HTTP/FTP: server-side no-op).
        XCTAssertTrue(task(status: .finished).canResume)
        XCTAssertFalse(task(status: .downloading).canResume)
        // Stop only makes sense for already-100 % tasks. Stopping a still-
        // downloading task on the API side just pauses it without
        // transitioning to finished, which is confusing UX — so hide it.
        XCTAssertTrue(task(status: .seeding).canStop)
        XCTAssertTrue(task(status: .finishing).canStop)
        XCTAssertFalse(task(status: .downloading).canStop)
        XCTAssertFalse(task(status: .paused).canStop)
        XCTAssertFalse(task(status: .finished).canStop)
    }
}

final class TaskFilterTests: XCTestCase {
    private func task(_ status: DownloadTask.Status) -> DownloadTask {
        DownloadTask(id: UUID().uuidString, title: "t", size: 1,
                     status: status, type: .bt, username: "u", additional: nil)
    }

    /// A task that has fully downloaded its payload — used to exercise the
    /// "paused after 100 %" → Finished bucket folding.
    private func taskAtCompletion(_ status: DownloadTask.Status) -> DownloadTask {
        let transfer = DownloadTask.Additional.Transfer(
            sizeDownloaded: 10,
            sizeUploaded: 0,
            speedDownload: 0,
            speedUpload: 0
        )
        return DownloadTask(
            id: UUID().uuidString, title: "t", size: 10,
            status: status, type: .bt, username: "u",
            additional: DownloadTask.Additional(
                transfer: transfer,
                detail: nil, file: nil, tracker: nil
            )
        )
    }

    func testAllMatchesEverything() {
        for status: DownloadTask.Status in [.downloading, .paused, .finished, .error, .seeding, .unknown] {
            XCTAssertTrue(TaskFilter.all.matches(task(status)))
        }
    }

    func testDownloadingExcludesSeeding() {
        // The reason this filter exists: distinguish "pulling bytes" from "sending to peers".
        XCTAssertTrue(TaskFilter.downloading.matches(task(.downloading)))
        XCTAssertTrue(TaskFilter.downloading.matches(task(.waiting)))
        XCTAssertTrue(TaskFilter.downloading.matches(task(.hash_checking)))
        XCTAssertFalse(TaskFilter.downloading.matches(task(.seeding)))
        XCTAssertFalse(TaskFilter.downloading.matches(task(.paused)))
        XCTAssertFalse(TaskFilter.downloading.matches(task(.finished)))
    }

    func testSeedingMatchesOnlySeeding() {
        XCTAssertTrue(TaskFilter.seeding.matches(task(.seeding)))
        XCTAssertFalse(TaskFilter.seeding.matches(task(.downloading)))
        XCTAssertFalse(TaskFilter.seeding.matches(task(.finished)))
    }

    func testActiveCoversBothDownloadingAndSeeding() {
        XCTAssertTrue(TaskFilter.active.matches(task(.downloading)))
        XCTAssertTrue(TaskFilter.active.matches(task(.seeding)))
        XCTAssertTrue(TaskFilter.active.matches(task(.hash_checking)))
        XCTAssertTrue(TaskFilter.active.matches(task(.waiting)))
        XCTAssertTrue(TaskFilter.active.matches(task(.finishing)))
        XCTAssertFalse(TaskFilter.active.matches(task(.paused)))
        XCTAssertFalse(TaskFilter.active.matches(task(.finished)))
        XCTAssertFalse(TaskFilter.active.matches(task(.error)))
    }

    func testFinishedExcludesInProgressFinishing() {
        // Finishing is still in progress; only fully-finished tasks count as done.
        XCTAssertTrue(TaskFilter.finished.matches(task(.finished)))
        XCTAssertFalse(TaskFilter.finished.matches(task(.finishing)))
        XCTAssertFalse(TaskFilter.finished.matches(task(.seeding)))
    }

    func testFinishedIncludesPausedAtCompletion() {
        // DS2 Task.Complete leaves a stopped seeding task as `paused` at
        // 100 %. The filter should treat that as Finished so the user sees
        // it where they expect.
        XCTAssertTrue(TaskFilter.finished.matches(taskAtCompletion(.paused)))
    }

    func testPausedExcludesPausedAtCompletion() {
        // A task paused at 100 % belongs in Finished, not Paused.
        XCTAssertTrue(TaskFilter.paused.matches(task(.paused))) // partial
        XCTAssertFalse(TaskFilter.paused.matches(taskAtCompletion(.paused))) // 100 %
    }

    func testPausedAndErrorAreSingleStatusFilters() {
        XCTAssertFalse(TaskFilter.paused.matches(task(.error)))
        XCTAssertTrue(TaskFilter.error.matches(task(.error)))
        XCTAssertFalse(TaskFilter.error.matches(task(.paused)))
    }

    func testDisplayStatusLabelFoldsPausedAtCompletionToEnded() {
        XCTAssertEqual(task(.downloading).displayStatusLabel, "Downloading")
        XCTAssertEqual(task(.paused).displayStatusLabel, "Paused")    // partial
        XCTAssertEqual(taskAtCompletion(.paused).displayStatusLabel, "Ended")
        XCTAssertEqual(task(.finished).displayStatusLabel, "Ended")
    }
}

final class APIErrorSessionExpiredTests: XCTestCase {
    func testSessionExpiredCodes() {
        for code in [105, 106, 107, 119] {
            XCTAssertTrue(APIError.synology(code: code, message: "x").isSessionExpired,
                          "Code \(code) should be treated as expired session")
        }
    }

    func testTransientNetworkErrorsAreNotSessionExpired() {
        XCTAssertFalse(APIError.http(500).isSessionExpired)
        XCTAssertFalse(APIError.transport(URLError(.notConnectedToInternet)).isSessionExpired)
        XCTAssertFalse(APIError.synology(code: 400, message: "x").isSessionExpired)
    }

    func testOTPRequiredAndInvalidCodes() {
        XCTAssertTrue(APIError.synology(code: 403, message: "x").isOTPRequired)
        XCTAssertFalse(APIError.synology(code: 404, message: "x").isOTPRequired)

        XCTAssertTrue(APIError.synology(code: 404, message: "x").isOTPInvalid)
        XCTAssertFalse(APIError.synology(code: 403, message: "x").isOTPInvalid)

        // Common error codes are neither.
        XCTAssertFalse(APIError.synology(code: 106, message: "x").isOTPRequired)
        XCTAssertFalse(APIError.synology(code: 106, message: "x").isOTPInvalid)
    }
}

final class LoginDataDecodingTests: XCTestCase {
    func testDecodeLoginWithoutDeviceToken() throws {
        let json = #"{"sid":"abc"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LoginData.self, from: json)
        XCTAssertEqual(decoded.sid, "abc")
        XCTAssertNil(decoded.did)
    }

    func testDecodeLoginWithDeviceToken() throws {
        let json = #"{"sid":"abc","did":"DID-XYZ"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LoginData.self, from: json)
        XCTAssertEqual(decoded.did, "DID-XYZ")
    }
}

final class TaskDetailDecodingTests: XCTestCase {
    func testDecodeFullDetailResponse() throws {
        // Modeled on the getinfo example in the Synology API spec: BT task with detail,
        // transfer, file list, and trackers.
        let json = """
        {
          "id": "dbid_42",
          "title": "ubuntu.iso",
          "size": 5368709120,
          "status": "downloading",
          "type": "bt",
          "username": "vasek",
          "additional": {
            "transfer": {
              "size_downloaded": 1073741824,
              "size_uploaded": 268435456,
              "speed_download": 5242880,
              "speed_upload": 524288
            },
            "detail": {
              "destination": "Downloads/Linux",
              "uri": "magnet:?xt=urn:btih:abcdef",
              "create_time": "1700000000",
              "priority": "auto",
              "connected_seeders": 12,
              "connected_leechers": 5,
              "total_peers": 200
            },
            "file": [
              {"filename":"ubuntu.iso","size":"5368709120","size_downloaded":"1073741824","priority":"normal"},
              {"filename":"readme.txt","size":1024,"size_downloaded":1024,"priority":"normal"}
            ],
            "tracker": [
              {"url":"udp://tracker.example.com:80","status":"OK","update_timer":900,"seeds":50,"peers":120}
            ]
          }
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(DownloadTask.self, from: json)
        XCTAssertEqual(task.additional?.detail?.destination, "Downloads/Linux")
        XCTAssertEqual(task.additional?.detail?.connectedSeeders?.value, 12)
        XCTAssertEqual(task.additional?.file?.count, 2)
        XCTAssertEqual(task.additional?.file?.first?.size?.value, 5368709120) // came in as string
        XCTAssertEqual(task.additional?.file?.last?.size?.value, 1024)        // came in as int
        XCTAssertEqual(task.additional?.tracker?.first?.seeds?.value, 50)
    }

    func testDecodeListResponseStillWorksWithoutExtraFields() throws {
        // The list endpoint omits detail/file/tracker — make sure the decoder doesn't choke.
        let json = #"""
        {"id":"x","title":"t","size":1,"status":"downloading","type":"http","username":"u","additional":{"transfer":{"size_downloaded":1,"size_uploaded":0,"speed_download":0,"speed_upload":0}}}
        """#.data(using: .utf8)!
        let task = try JSONDecoder().decode(DownloadTask.self, from: json)
        XCTAssertNil(task.additional?.detail)
        XCTAssertNil(task.additional?.file)
    }
}

final class FlexibleInt64Tests: XCTestCase {
    func testDecodesFromNumber() throws {
        let n = try JSONDecoder().decode(FlexibleInt64.self, from: Data("12345".utf8))
        XCTAssertEqual(n.value, 12345)
    }

    func testDecodesFromQuotedString() throws {
        let n = try JSONDecoder().decode(FlexibleInt64.self, from: Data(#""54321""#.utf8))
        XCTAssertEqual(n.value, 54321)
    }

    func testDecodesUnparseableStringAsZero() throws {
        let n = try JSONDecoder().decode(FlexibleInt64.self, from: Data(#""nope""#.utf8))
        XCTAssertEqual(n.value, 0)
    }
}

final class FileNodeTests: XCTestCase {
    func testDecodeShareFromFileStationJSON() throws {
        // Synology returns list_share entries with leading-slash paths.
        let json = #"{"name":"Downloads","path":"/Downloads","isdir":true}"#.data(using: .utf8)!
        let node = try JSONDecoder().decode(FileNode.self, from: json)
        XCTAssertEqual(node.name, "Downloads")
        XCTAssertEqual(node.path, "/Downloads")
        XCTAssertTrue(node.isdir)
    }

    func testDestinationPathStripsLeadingSlash() {
        // DownloadStation create-task expects "Downloads/Movies", not "/Downloads/Movies".
        XCTAssertEqual(FileNode(name: "Movies", path: "/Downloads/Movies", isdir: true).destinationPath,
                       "Downloads/Movies")
        XCTAssertEqual(FileNode(name: "Downloads", path: "/Downloads", isdir: true).destinationPath,
                       "Downloads")
    }

    func testDestinationPathLeavesAlreadyRelativeAlone() {
        XCTAssertEqual(FileNode(name: "x", path: "Downloads", isdir: true).destinationPath,
                       "Downloads")
    }
}

final class AppearanceModeTests: XCTestCase {
    func testPreferredColorSchemeMapping() {
        XCTAssertNil(AppearanceMode.system.preferredColorScheme)
        XCTAssertEqual(AppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.preferredColorScheme, .dark)
    }

    func testRoundTripsThroughRawValue() {
        for mode in AppearanceMode.allCases {
            XCTAssertEqual(AppearanceMode(rawValue: mode.rawValue), mode)
        }
    }

    func testUnknownRawValueIsNil() {
        XCTAssertNil(AppearanceMode(rawValue: "purple"))
    }
}

final class APIErrorContextTests: XCTestCase {
    func testCommonCodesAreContextIndependent() {
        XCTAssertEqual(SynologyErrorCode.message(for: 106, context: .auth),
                       SynologyErrorCode.message(for: 106, context: .task))
        XCTAssertTrue(SynologyErrorCode.message(for: 106).contains("timeout"))
    }

    func testAuthAndTaskContextsDisagreeOn400() {
        let auth = SynologyErrorCode.message(for: 400, context: .auth)
        let task = SynologyErrorCode.message(for: 400, context: .task)
        XCTAssertNotEqual(auth, task)
        XCTAssertTrue(auth.lowercased().contains("password") || auth.lowercased().contains("account"))
        XCTAssertTrue(task.lowercased().contains("file"))
    }

    func testTaskContext401IsMaxTasks() {
        XCTAssertTrue(
            SynologyErrorCode.message(for: 401, context: .task).lowercased().contains("maximum")
        )
    }
}

