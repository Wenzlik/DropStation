import Foundation
import SwiftUI

/// Drives the post-login Dashboard. Phase-1 scope: poll the same
/// `listTasks` endpoint the task list already uses, derive a handful
/// of aggregate stats, and expose a "recently completed" slice for
/// the dashboard's completed-downloads section.
///
/// Polls independently of `TaskListViewModel` for now. When the user
/// is on the Dashboard tab the auto-refresh runs here; switching to
/// the Downloads tab spins up the list's own refresh on top of this
/// one. The duplicate is acceptable for Phase 1 — sharing a single
/// task store is on the 0.5.0 roadmap (DownloadTaskStore).
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: SynologyAPIClient
    /// Invoked when a `listTasks` call returns Synology error 105.
    /// Wired to `SessionStore.handleUnauthorized` so the recovery
    /// card replaces the tab-bar shell cleanly — mirrors how
    /// `TaskListViewModel` propagates the same condition.
    private let onUnauthorized: (String) -> Void
    private var refreshTimer: Timer?

    init(client: SynologyAPIClient, onUnauthorized: @escaping (String) -> Void = { _ in }) {
        self.client = client
        self.onUnauthorized = onUnauthorized
    }

    // MARK: - Derived stats

    /// Anything DSM is currently working on, in either direction —
    /// matches `TaskFilter.active` so the dashboard count agrees
    /// with what the list filter would show.
    var activeCount: Int {
        tasks.filter { TaskFilter.active.matches($0) }.count
    }

    var failedCount: Int {
        tasks.filter { TaskFilter.error.matches($0) }.count
    }

    var totalDownloadSpeed: Int64 {
        tasks.reduce(0) { $0 + ($1.additional?.transfer?.speedDownload.value ?? 0) }
    }

    var totalUploadSpeed: Int64 {
        tasks.reduce(0) { $0 + ($1.additional?.transfer?.speedUpload.value ?? 0) }
    }

    /// Up to five most-recently-completed tasks, newest first. Tasks
    /// without a `completed_time` (e.g. paused-at-100 % rows from
    /// older DSM builds that didn't stamp one) sort to the end of
    /// the slice.
    var recentlyCompleted: [DownloadTask] {
        tasks
            .filter { TaskFilter.finished.matches($0) }
            .sorted(by: .dateCompleted, direction: .descending)
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await client.listTasks()
            errorMessage = nil
        } catch let error as APIError where error.isUnauthorized {
            stopAutoRefresh()
            onUnauthorized(error.localizedDescription)
        } catch let error as APIError where error.isTransient {
            // Same swallow-and-retry pattern as TaskListViewModel.
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
