import Foundation
import SwiftUI

@MainActor
final class TaskDetailViewModel: ObservableObject {
    @Published private(set) var task: DownloadTask
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SynologyAPIClient
    private var refreshTimer: Timer?

    init(task: DownloadTask, client: SynologyAPIClient) {
        self.task = task
        self.client = client
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            task = try await client.getTaskInfo(id: task.id)
            errorMessage = nil
        } catch let error as APIError where error.isTransient {
            // Same logic as TaskListViewModel: swallow connectivity blips during
            // the background poll, the next tick will pick the data back up.
            #if DEBUG
            print("[DropStation] detail refresh transient error, ignoring: \(error.localizedDescription)")
            #endif
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() async {
        do {
            try await client.pauseTasks(ids: [task.id])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resume() async {
        do {
            try await client.resumeTasks(ids: [task.id])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
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
