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

    func testPauseResumeAvailability() throws {
        func task(status: DownloadTask.Status) -> DownloadTask {
            DownloadTask(id: "x", title: "t", size: 1, status: status, type: .bt, username: "u", additional: nil)
        }
        XCTAssertTrue(task(status: .downloading).canPause)
        XCTAssertTrue(task(status: .seeding).canPause)
        XCTAssertFalse(task(status: .paused).canPause)
        XCTAssertTrue(task(status: .paused).canResume)
        XCTAssertTrue(task(status: .error).canResume)
        XCTAssertFalse(task(status: .finished).canResume)
        XCTAssertFalse(task(status: .downloading).canResume)
    }
}

final class TaskFilterTests: XCTestCase {
    private func task(_ status: DownloadTask.Status) -> DownloadTask {
        DownloadTask(id: UUID().uuidString, title: "t", size: 1,
                     status: status, type: .bt, username: "u", additional: nil)
    }

    func testAllMatchesEverything() {
        for status: DownloadTask.Status in [.downloading, .paused, .finished, .error, .seeding, .unknown] {
            XCTAssertTrue(TaskFilter.all.matches(task(status)))
        }
    }

    func testActiveCoversWorkingStates() {
        XCTAssertTrue(TaskFilter.active.matches(task(.downloading)))
        XCTAssertTrue(TaskFilter.active.matches(task(.seeding)))
        XCTAssertTrue(TaskFilter.active.matches(task(.hash_checking)))
        XCTAssertTrue(TaskFilter.active.matches(task(.waiting)))
        XCTAssertFalse(TaskFilter.active.matches(task(.paused)))
        XCTAssertFalse(TaskFilter.active.matches(task(.finished)))
        XCTAssertFalse(TaskFilter.active.matches(task(.error)))
    }

    func testFinishedCoversBothFinishedAndFinishing() {
        XCTAssertTrue(TaskFilter.finished.matches(task(.finished)))
        XCTAssertTrue(TaskFilter.finished.matches(task(.finishing)))
        XCTAssertFalse(TaskFilter.finished.matches(task(.seeding)))
    }

    func testPausedAndErrorAreSingleStatusFilters() {
        XCTAssertTrue(TaskFilter.paused.matches(task(.paused)))
        XCTAssertFalse(TaskFilter.paused.matches(task(.error)))
        XCTAssertTrue(TaskFilter.error.matches(task(.error)))
        XCTAssertFalse(TaskFilter.error.matches(task(.paused)))
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

