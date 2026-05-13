import Foundation
import SwiftUI

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var filter: TaskFilter = .all

    var filteredTasks: [DownloadTask] {
        tasks.filter { filter.matches($0) }
    }

    func count(for filter: TaskFilter) -> Int {
        tasks.filter { filter.matches($0) }.count
    }

    /// Sum of download speed across all tasks (whatever the filter is — represents the NAS, not the view).
    var totalDownloadSpeed: Int64 {
        tasks.reduce(0) { $0 + ($1.additional?.transfer?.speedDownload.value ?? 0) }
    }

    var totalUploadSpeed: Int64 {
        tasks.reduce(0) { $0 + ($1.additional?.transfer?.speedUpload.value ?? 0) }
    }

    private let client: SynologyAPIClient
    private var refreshTimer: Timer?

    init(client: SynologyAPIClient) {
        self.client = client
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await client.listTasks()
            // Drop any stale error banner once a fresh poll succeeds.
            errorMessage = nil
        } catch let error as APIError where error.isTransient {
            // Network/timeout/5xx during the background refresh. Don't alert the
            // user — the next 5 s tick will almost certainly recover.
            #if DEBUG
            print("[SynoGet] refresh transient error, ignoring: \(error.localizedDescription)")
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(uri: String, destination: String? = nil) async {
        do {
            try await client.createTask(uri: uri, destination: destination)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(fileData: Data, filename: String, destination: String? = nil) async {
        do {
            try await client.createTask(fileData: fileData, filename: filename, destination: destination)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause(_ task: DownloadTask) async {
        do {
            try await client.pauseTasks(ids: [task.id])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume(_ task: DownloadTask) async {
        do {
            try await client.resumeTasks(ids: [task.id])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ task: DownloadTask) async {
        do {
            try await client.deleteTask(id: task.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
