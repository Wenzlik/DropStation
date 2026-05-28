import Foundation
import SwiftUI
import Combine

/// View-local state for the Dashboard tab. After the 0.5.1
/// `DownloadTaskStore` extraction, this viewmodel no longer owns
/// the `tasks` array or the polling timer — it derives everything
/// from the shared store and only keeps the dashboard-specific
/// presentation state (hostname label, free-disk placeholder).
///
/// Conceptually:
///
///   - `DownloadTaskStore` = data layer (one instance per app).
///   - `DashboardViewModel` = "how does the dashboard read the
///     data" — the hero state classifier, the recently-completed
///     slice, the count derivations.
///
/// The view forwards changes from the store via the manual
/// `objectWillChange` republish below, so observing the viewmodel
/// is enough; views don't have to subscribe to both.
@MainActor
final class DashboardViewModel: ObservableObject {
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

    private let store: DownloadTaskStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: DownloadTaskStore, hostname: String) {
        self.store = store
        self.hostname = hostname
        // Republish the store's change signal through this view
        // model so views observing only DashboardViewModel still
        // re-render on store updates. Cheaper for callers than
        // pulling DownloadTaskStore in as a second @EnvironmentObject
        // everywhere.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Store passthrough

    var tasks: [DownloadTask] { store.tasks }
    var hasLoadedOnce: Bool { store.hasLoadedOnce }
    var isOnline: Bool { store.isOnline }
    var isLoading: Bool { store.isLoading }
    var errorMessage: String? {
        get { store.errorMessage }
        set { store.errorMessage = newValue }
    }

    func refresh() async {
        await store.refresh()
    }

    func createTask(uri: String, destination: String? = nil) async {
        await store.createTask(uri: uri, destination: destination)
    }

    func createTask(fileData: Data, filename: String, destination: String? = nil) async {
        await store.createTask(fileData: fileData, filename: filename, destination: destination)
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

    /// Three-way classifier for the dashboard hero. Distinguishes
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

    /// Up to three currently-moving tasks, sorted by combined
    /// throughput descending. Drives the "Active now" dashboard
    /// section when at least one task is in flight.
    ///
    /// "Active" here is stricter than `TaskFilter.active`: we only
    /// surface tasks where the NAS is actually moving bytes (either
    /// direction) or is in a downloading-flow state that genuinely
    /// belongs in a live-activity overview (hash_checking, waiting,
    /// finishing, …). Bare `.seeding` with zero upload doesn't make
    /// the cut — it appears in Recently completed instead so the
    /// "active" feed reads as live.
    ///
    /// Sort key is the combined download+upload byte rate so the
    /// dashboard surfaces the most-impactful transfer first; ties
    /// fall back to title for determinism (the 5 s poll re-runs this
    /// continuously, so a flapping tiebreak would jitter the
    /// section visually).
    var activeTransfers: [DownloadTask] {
        tasks
            .filter(Self.isActiveTransfer)
            .sorted { lhs, rhs in
                let lt = Self.throughput(of: lhs)
                let rt = Self.throughput(of: rhs)
                if lt == rt { return lhs.title < rhs.title }
                return lt > rt
            }
            .prefix(3)
            .map { $0 }
    }

    /// True when the active section should take precedence over
    /// Recently completed. Drives the dashboard's state-aware
    /// section ordering — when nothing is moving, the historical
    /// completed feed takes the top slot.
    var hasActiveTransfers: Bool { !activeTransfers.isEmpty }

    /// Up to five completed tasks, newest first. Treats a seeding
    /// torrent as completed content — from the user's point of view
    /// the download is done and the file is locally available; the
    /// fact that DSM is still sharing it with peers is a bonus, not
    /// a "still in progress" state. Tasks shown in `activeTransfers`
    /// are excluded so the same row never appears in both sections
    /// (a seeding task that is currently uploading lives in Active;
    /// a seeding task with no upload flow lives here).
    ///
    /// Tasks without a `completed_time` sort to the end of the slice.
    var recentlyCompleted: [DownloadTask] {
        let activeIds = Set(activeTransfers.map(\.id))
        return tasks
            .filter { !activeIds.contains($0.id) && Self.isCompletedContent($0) }
            .sorted(by: .dateCompleted, direction: .descending)
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Section predicates

    /// Combined down+up bytes-per-second for the given task. Used as
    /// the sort key for `activeTransfers` and as the "is this thing
    /// actually moving" probe.
    private static func throughput(of task: DownloadTask) -> Int64 {
        (task.additional?.transfer?.speedDownload.value ?? 0)
        + (task.additional?.transfer?.speedUpload.value ?? 0)
    }

    /// A task that belongs in the dashboard's "Active now" section:
    /// either currently moving bytes in some direction, or sitting
    /// in a state that reads as live work-in-progress to the user
    /// (hash-checking a freshly-added torrent, waiting in queue, …).
    /// Paused / finished / error are excluded — they have nothing to
    /// surface in a live-activity panel.
    private static func isActiveTransfer(_ task: DownloadTask) -> Bool {
        if throughput(of: task) > 0 { return true }
        switch task.status {
        case .downloading, .hash_checking, .waiting, .finishing,
             .extracting, .filehosting_waiting:
            return true
        default:
            return false
        }
    }

    /// "Effectively completed" — the download payload is done and
    /// the file is locally available. Folds the three representations
    /// DSM uses for this state together: the API-level `.finished`,
    /// the BT post-Complete `.paused`-at-100 % shape, and `.seeding`
    /// (the user already got the file; uploads to peers are extra).
    private static func isCompletedContent(_ task: DownloadTask) -> Bool {
        switch task.status {
        case .finished, .seeding:
            return true
        case .paused:
            return task.isAtCompletion
        default:
            return false
        }
    }
}
