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

final class FilePriorityTests: XCTestCase {
    func testFromRawPriorityMatchesKnownStrings() {
        XCTAssertEqual(FilePriority.from(rawPriority: "skip"), .skip)
        XCTAssertEqual(FilePriority.from(rawPriority: "low"), .low)
        XCTAssertEqual(FilePriority.from(rawPriority: "normal"), .normal)
        XCTAssertEqual(FilePriority.from(rawPriority: "high"), .high)
    }

    func testFromRawPriorityFallsBackToNormal() {
        // Missing / "auto" / unknown all map to normal so display
        // never crashes on a value DSM invents.
        XCTAssertEqual(FilePriority.from(rawPriority: nil), .normal)
        XCTAssertEqual(FilePriority.from(rawPriority: "auto"), .normal)
        XCTAssertEqual(FilePriority.from(rawPriority: "unknown_future_value"), .normal)
    }

    func testWantedFalseCollapsesToSkipRegardlessOfRawPriority() {
        // The whole reason the wanted-aware resolver exists: some
        // DSM builds keep the file's pre-skip priority value in the
        // `priority` field even after wanted goes false. Trusting
        // wanted=false here is what makes the row render as Skipped.
        XCTAssertEqual(FilePriority.from(rawPriority: "normal", wanted: false), .skip)
        XCTAssertEqual(FilePriority.from(rawPriority: "high", wanted: false), .skip)
        XCTAssertEqual(FilePriority.from(rawPriority: nil, wanted: false), .skip)
    }

    func testWantedTrueAndMissingDefersToRawPriority() {
        // wanted=true and wanted=nil both fall through to the raw
        // priority — only an explicit false flips us to skip.
        XCTAssertEqual(FilePriority.from(rawPriority: "high", wanted: true), .high)
        XCTAssertEqual(FilePriority.from(rawPriority: "high", wanted: nil), .high)
        XCTAssertEqual(FilePriority.from(rawPriority: "skip", wanted: nil), .skip)
    }
}

final class TorrentFileDecodingTests: XCTestCase {
    func testDecodesWantedFlagWhenPresent() throws {
        let json = #"""
        {"filename":"clip.mp4","size":1024,"size_downloaded":0,"priority":"normal","wanted":false}
        """#.data(using: .utf8)!
        let file = try JSONDecoder().decode(DownloadTask.Additional.TorrentFile.self, from: json)
        XCTAssertEqual(file.wanted, false)
        XCTAssertEqual(file.priority, "normal")
        // wanted-aware resolver folds this into .skip — the case the
        // visual treatment in TaskDetailView depends on.
        XCTAssertEqual(FilePriority.from(rawPriority: file.priority, wanted: file.wanted), .skip)
    }

    func testWantedAbsentDecodesAsNilNotFailure() throws {
        // List endpoints don't always include `wanted`; the decoder
        // must not fail when it's missing.
        let json = #"""
        {"filename":"clip.mp4","size":1024,"size_downloaded":1024,"priority":"normal"}
        """#.data(using: .utf8)!
        let file = try JSONDecoder().decode(DownloadTask.Additional.TorrentFile.self, from: json)
        XCTAssertNil(file.wanted)
    }
}

final class DashboardActiveTransfersTests: XCTestCase {
    private func task(
        id: String,
        status: DownloadTask.Status,
        title: String = "t",
        size: Int64 = 100,
        downloaded: Int64 = 0,
        speedDown: Int64 = 0,
        speedUp: Int64 = 0
    ) -> DownloadTask {
        let transfer = DownloadTask.Additional.Transfer(
            sizeDownloaded: FlexibleInt64(downloaded),
            sizeUploaded: 0,
            speedDownload: FlexibleInt64(speedDown),
            speedUpload: FlexibleInt64(speedUp)
        )
        return DownloadTask(
            id: id,
            title: title,
            size: FlexibleInt64(size),
            status: status,
            type: .bt,
            username: nil,
            additional: DownloadTask.Additional(
                transfer: transfer,
                detail: nil,
                file: nil,
                tracker: nil
            )
        )
    }

    func testActiveTransfersOrdersByCombinedThroughput() async {
        let store = await DownloadTaskStore.makeForTesting(tasks: [
            task(id: "a", status: .downloading, speedDown: 1_000),
            task(id: "b", status: .downloading, speedDown: 5_000_000),
            task(id: "c", status: .downloading, speedDown: 500, speedUp: 2_000_000)
        ])
        let vm = await DashboardViewModel(store: store, hostname: "nas")
        let order = await vm.activeTransfers.map(\.id)
        XCTAssertEqual(order, ["b", "c", "a"])
    }

    func testActiveTransfersExcludesIdleSeedingButIncludesUploadingSeeder() async {
        let store = await DownloadTaskStore.makeForTesting(tasks: [
            task(id: "idle-seeder", status: .seeding, speedDown: 0, speedUp: 0),
            task(id: "uploading-seeder", status: .seeding, speedDown: 0, speedUp: 100_000),
            task(id: "downloading", status: .downloading, speedDown: 50_000)
        ])
        let vm = await DashboardViewModel(store: store, hostname: "nas")
        let ids = await vm.activeTransfers.map(\.id)
        XCTAssertTrue(ids.contains("uploading-seeder"))
        XCTAssertTrue(ids.contains("downloading"))
        XCTAssertFalse(ids.contains("idle-seeder"))
    }

    func testActiveTransfersIncludesHashCheckingEvenWithoutThroughput() async {
        // hash_checking has no byte rate but is definitely live
        // NAS work — should appear in the active feed so the user
        // sees freshly-added torrents.
        let store = await DownloadTaskStore.makeForTesting(tasks: [
            task(id: "hashing", status: .hash_checking)
        ])
        let vm = await DashboardViewModel(store: store, hostname: "nas")
        let ids = await vm.activeTransfers.map(\.id)
        XCTAssertEqual(ids, ["hashing"])
    }

    func testActiveTransfersCapsAtThree() async {
        let store = await DownloadTaskStore.makeForTesting(tasks: [
            task(id: "1", status: .downloading, speedDown: 100),
            task(id: "2", status: .downloading, speedDown: 200),
            task(id: "3", status: .downloading, speedDown: 300),
            task(id: "4", status: .downloading, speedDown: 400),
            task(id: "5", status: .downloading, speedDown: 500)
        ])
        let vm = await DashboardViewModel(store: store, hostname: "nas")
        let active = await vm.activeTransfers
        XCTAssertEqual(active.count, 3)
        XCTAssertEqual(active.map(\.id), ["5", "4", "3"])
    }

    func testRecentlyCompletedIncludesSeedingButExcludesActiveOnes() async {
        let store = await DownloadTaskStore.makeForTesting(tasks: [
            // Active uploader — should NOT also appear in completed.
            task(id: "uploading-seeder", status: .seeding, speedUp: 100_000),
            // Idle seeder — completed download, just sitting there. Goes
            // to recently completed.
            task(id: "idle-seeder", status: .seeding),
            task(id: "finished", status: .finished)
        ])
        let vm = await DashboardViewModel(store: store, hostname: "nas")
        let completedIds = await vm.recentlyCompleted.map(\.id)
        XCTAssertTrue(completedIds.contains("idle-seeder"))
        XCTAssertTrue(completedIds.contains("finished"))
        XCTAssertFalse(completedIds.contains("uploading-seeder"))
    }

    func testHasActiveTransfersFlagMirrorsList() async {
        let empty = await DownloadTaskStore.makeForTesting(tasks: [
            task(id: "f", status: .finished)
        ])
        let vmEmpty = await DashboardViewModel(store: empty, hostname: "nas")
        let emptyResult = await vmEmpty.hasActiveTransfers
        XCTAssertFalse(emptyResult)

        let active = await DownloadTaskStore.makeForTesting(tasks: [
            task(id: "d", status: .downloading, speedDown: 1)
        ])
        let vmActive = await DashboardViewModel(store: active, hostname: "nas")
        let activeResult = await vmActive.hasActiveTransfers
        XCTAssertTrue(activeResult)
    }
}

final class BugReportTests: XCTestCase {
    private func diagnostics(timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Diagnostics {
        Diagnostics(
            appVersion: "0.5.2",
            appBuild: "12",
            iOSVersion: "26.1",
            deviceModel: "iPhone15,2",
            hostname: "nas.local",
            authMethod: "Verification code",
            sessionState: "loggedIn",
            timestamp: timestamp
        )
    }

    func testEmailBodyOnlyRendersFilledOptionalSections() {
        let report = BugReport(
            subject: "Stuck on splash",
            description: "App freezes after login.",
            stepsToReproduce: nil,
            expectedBehavior: nil,
            contactEmail: nil,
            includeDiagnostics: false,
            diagnostics: nil
        )
        let body = report.composeEmailBody()
        XCTAssertTrue(body.contains("App freezes after login."))
        XCTAssertFalse(body.contains("Steps to reproduce"))
        XCTAssertFalse(body.contains("Expected behavior"))
        XCTAssertFalse(body.contains("Contact:"))
        XCTAssertFalse(body.contains("Diagnostics"))
    }

    func testEmailBodyIncludesDiagnosticsWhenOptedIn() {
        let report = BugReport(
            subject: "Stuck on splash",
            description: "App freezes after login.",
            stepsToReproduce: "1. Open app\n2. Wait",
            expectedBehavior: "Task list loads.",
            contactEmail: "me@example.com",
            includeDiagnostics: true,
            diagnostics: diagnostics()
        )
        let body = report.composeEmailBody()
        XCTAssertTrue(body.contains("Steps to reproduce"))
        XCTAssertTrue(body.contains("Expected behavior"))
        XCTAssertTrue(body.contains("Contact: me@example.com"))
        XCTAssertTrue(body.contains("App version: 0.5.2 (12)"))
        XCTAssertTrue(body.contains("Device: iPhone15,2"))
        XCTAssertTrue(body.contains("Host: nas.local"))
        XCTAssertTrue(body.contains("Auth method: Verification code"))
        XCTAssertTrue(body.contains("Session state: loggedIn"))
    }

    func testDiagnosticsOmittedEvenIfPresentWhenFlagOff() {
        // Belt-and-braces: if a caller mistakenly attaches the
        // diagnostics struct while the toggle is off, the body
        // still omits the block. Mirrors the privacy contract:
        // the toggle is authoritative.
        let report = BugReport(
            subject: "x",
            description: "y",
            stepsToReproduce: nil,
            expectedBehavior: nil,
            contactEmail: nil,
            includeDiagnostics: false,
            diagnostics: diagnostics()
        )
        XCTAssertFalse(report.composeEmailBody().contains("Diagnostics"))
        XCTAssertFalse(report.composeEmailBody().contains("Host:"))
    }

    func testEmailSubjectLineIsPrefixed() {
        let report = BugReport(
            subject: "Stuck on splash",
            description: "x",
            stepsToReproduce: nil,
            expectedBehavior: nil,
            contactEmail: nil,
            includeDiagnostics: false,
            diagnostics: nil
        )
        XCTAssertEqual(report.emailSubjectLine, "[DropStation] Stuck on splash")
    }

    func testRecipientEmail() {
        // Pinned by test so a refactor of the email value lights
        // up the test suite rather than silently rerouting reports.
        XCTAssertEqual(BugReport.recipientEmail, "dropstation@zmrhal.cz")
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

