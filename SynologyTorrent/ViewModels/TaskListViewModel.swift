import Foundation
import SwiftUI

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(uri: String) async {
        do {
            try await client.createTask(uri: uri)
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
