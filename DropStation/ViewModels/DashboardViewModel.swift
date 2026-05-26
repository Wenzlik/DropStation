import Foundation
import SwiftUI

/// Drives the post-login Dashboard. Phase 2 extends Phase 1 with
/// NAS context (hostname / online state / free-disk placeholder)
/// and an idle/active derivation so the hero card can show a
/// friendly "All downloads completed · NAS is idle" message instead
/// of a row of zeros when nothing is transferring.
///
/// Polls independently of `TaskListViewModel` for now. Sharing a
/// single task store is on the 0.5 roadmap (DownloadTaskStore).
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    @Published private(set) var isLoading = false
    /// True once the first refresh has come back (success or handled
    /// failure). Drives the first-load skeleton state — distinct
    /// from `isLoading`, which flips on every poll.
    @Published private(set) var hasLoadedOnce = false
    /// True when the most recent refresh succeeded. Drives the
    /// Online / Offline badge in the hero card. Transient failures
    /// (the kind the polling loop intentionally swallows) flip this
    /// to false; the next successful tick flips it back.
    @Published private(set) var isOnline = true
    @Published var errorMessage: String?

    /// Free disk space on the configured volume, in bytes. Phase 2
    /// keeps this as architectural placeholder (always `nil` for
    /// now) — wiring `SYNO.FileStation.Info` or `SYNO.Core.Storage`
    /// will land in a follow-up commit. The hero card already
    /// renders the row conditionally so the value can drop in
    /// without further plumbing.
    @Published private(set) var freeDiskBytes: Int64? = nil

    /// Human-readable label for the NAS in the hero card. Phase 2
    /// uses the configured host (e.g. "nas.local" or an IP); when
    /// `SYNO.FileStation.Info` is wired up later, this can be
    /// upgraded to the real device name ("DS920+").
    let hostname: String

    private let client: SynologyAPIClient
    /// Invoked when a `listTasks` call returns Synology error 105.
    /// Wired to `SessionStore.handleUnauthorized` so the recovery
    /// card replaces the tab-bar shell cleanly — mirrors how
    /// `TaskListViewModel` propagates the same condition.
    private let onUnauthorized: (String) -> Void
    private var refreshTimer: Timer?

    init(
        client: SynologyAPIClient,
        hostname: String,
        onUnauthorized: @escaping (String) -> Void = { _ in }
    ) {
        self.client = client
        self.hostname = hostname
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

    /// Three-way classifier for the dashboard hero. Replaces the
    /// previous boolean `isIdle` so the view can distinguish
    /// "tasks exist but nothing is transferring right now" from
    /// "the queue is empty" — the former is queue-paused / waiting
    /// / hash-checking, the latter is genuine done-for-now.
    enum HeroState {
        /// Bytes are moving in at least one direction.
        case transferring
        /// Tasks exist on the NAS but neither direction is moving
        /// (everything paused, finishing, waiting, or finished).
        case taskIdle
        /// No tasks at all on the NAS.
        case empty
    }

    var heroState: HeroState {
        if totalDownloadSpeed > 0 || totalUploadSpeed > 0 { return .transferring }
        if tasks.isEmpty { return .empty }
        return .taskIdle
    }

    /// Total number of tasks on the NAS, regardless of status.
    /// Drives the focal "X Tasks" headline in the `.taskIdle`
    /// hero state.
    var totalTaskCount: Int { tasks.count }

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
        defer {
            isLoading = false
            hasLoadedOnce = true
        }
        do {
            tasks = try await client.listTasks()
            errorMessage = nil
            isOnline = true
        } catch let error as APIError where error.isUnauthorized {
            stopAutoRefresh()
            onUnauthorized(error.localizedDescription)
        } catch let error as APIError where error.isTransient {
            // Same swallow-and-retry pattern as TaskListViewModel.
            // The badge flips to Offline so the user knows we're
            // currently out of contact; the next successful tick
            // flips it back.
            isOnline = false
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
