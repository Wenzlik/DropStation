import Foundation
import SwiftUI

/// Shared post-login data layer. Owns the `[DownloadTask]` array
/// and the 5 s `Timer`-driven polling loop that previously lived
/// on `DashboardViewModel` and `TaskListViewModel` independently;
/// each tab's view model now reads from this single store instead
/// of running its own poll.
///
/// Eliminates the duplicate listTasks call per tick that 0.5.0
/// shipped with, and gives Dashboard and Downloads tabs a single
/// source of truth for `tasks` / `hasLoadedOnce` / `isOnline`.
/// Also the foundation the 0.5.1+ work builds on:
///
///   - Notifications need to diff "what just finished" against the
///     previous tick — needs a single canonical tick to diff
///     against, which the store now is.
///   - Widgets / lock-screen surfaces want to read the same task
///     state without re-implementing a poll.
///   - Background refresh (`BGAppRefreshTask`) gets one place to
///     hand the foreground task list off to.
///   - Multi-server (0.7) becomes "one store instance per
///     configured server" rather than a coordination problem
///     across N view models.
///
/// Surface mirrors what the two view models exposed in 0.5.0, so
/// callers migrate by replacing `viewModel.tasks` etc. with
/// `store.tasks`. Action mutations (create / pause / stop /
/// resume / delete) are wrapped here so the call site doesn't
/// have to repeat the "fire request, then refresh" dance.
///
/// Lifecycle. The store is injected as `@EnvironmentObject` from
/// `DropStationApp`, so a single instance lives for the lifetime
/// of the process. `RootView` drives the polling timer by
/// observing `SessionStore.state`: `.loggedIn` enter →
/// `startAutoRefresh` + initial refresh; any other state →
/// `stopAutoRefresh`. View-level `.task` modifiers no longer
/// own the lifecycle (they did in 0.5.0 because each view model
/// owned its own poll).
@MainActor
final class DownloadTaskStore: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []
    /// True while a poll request is in flight. Distinct from
    /// `hasLoadedOnce` — `isLoading` flips on every tick;
    /// `hasLoadedOnce` only flips once.
    @Published private(set) var isLoading = false
    /// Flipped true after the first refresh return (success or
    /// handled failure). Drives the first-load skeleton state in
    /// Dashboard and the empty-state-vs-loading discrimination
    /// in Downloads.
    @Published private(set) var hasLoadedOnce = false
    /// True when the most recent refresh succeeded. Transient
    /// failures (the kind the polling loop intentionally swallows)
    /// flip this to false; the next successful tick flips it
    /// back. Drives the Dashboard hero's Online / Offline badge.
    @Published private(set) var isOnline = true
    /// Surface for non-transient, non-105 errors observed during
    /// polling. The two original view models each had their own
    /// errorMessage; for the store this is the canonical channel.
    @Published var errorMessage: String?

    /// Free space (bytes) on the NAS volume that hosts the user's
    /// shared folders, or `nil` when unknown. Drives the hero
    /// card's "X free" metric. Fetched on a slower cadence than
    /// the task list (free disk barely moves second-to-second) —
    /// see `refreshStorageIfStale`. Decorative: a fetch failure
    /// never surfaces a banner or touches the session.
    @Published private(set) var freeDiskBytes: Int64?

    /// Throttle gate for the free-disk probe. Free space changes
    /// slowly, so we refresh it at most once per
    /// `storageRefreshInterval` rather than on every 5 s task tick.
    private var lastStorageFetch: Date?
    private let storageRefreshInterval: TimeInterval = 60

    private let client: SynologyAPIClient
    /// Forwards Synology error 105 to `SessionStore.handleUnauthorized`.
    /// Wired by the App-level injector with a weak capture of the
    /// session store, so the dependency direction stays one-way
    /// (Store → SessionStore via callback, not Store ← SessionStore
    /// import).
    private let onUnauthorized: (String) -> Void
    private var refreshTimer: Timer?
    /// Drives the Live Activity (Dynamic Island / lock screen) for
    /// active downloads. Fed the latest task list after every poll;
    /// starts/updates while something is downloading, ends when not.
    private let activityController: DownloadActivityController

    init(
        client: SynologyAPIClient,
        serverName: String = "DropStation",
        onUnauthorized: @escaping (String) -> Void = { _ in }
    ) {
        self.client = client
        self.onUnauthorized = onUnauthorized
        self.activityController = DownloadActivityController(serverName: serverName)
    }

    // MARK: - Polling

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
            activityController.sync(with: tasks)
            // Session just confirmed valid by the task fetch — a
            // good moment to opportunistically refresh free disk,
            // throttled so it doesn't ride every 5 s tick.
            await refreshStorageIfStale()
        } catch let error as APIError where error.isUnauthorized {
            // 105 — the SID DSM gave us isn't valid for Download
            // Station any more. Stop the poll loop so we don't
            // keep hammering with a dead session, and let the
            // SessionStore route to the recovery card.
            stopAutoRefresh()
            onUnauthorized(error.localizedDescription)
        } catch let error as APIError where error.isTransient {
            // Network / DNS / TLS / 5xx blips don't surface as
            // a banner — keep the cached `tasks` so the UI
            // stays stable. The badge flips to Offline; next
            // success flips it back.
            isOnline = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refresh free-disk space if the throttle window has elapsed.
    /// Called from `refresh()` right after a successful task fetch.
    /// Throttled to `storageRefreshInterval` (attempts, not just
    /// successes, advance the gate) so a persistently-failing probe
    /// doesn't hammer the endpoint every tick. Fully decorative:
    /// any error is swallowed, the last known value stays put, and
    /// the session / task polling are never affected.
    private func refreshStorageIfStale() async {
        let now = Date()
        if let last = lastStorageFetch, now.timeIntervalSince(last) < storageRefreshInterval {
            return
        }
        lastStorageFetch = now
        do {
            if let free = try await client.volumeFreeSpace() {
                freeDiskBytes = free
            }
        } catch {
            // Decorative — never surface, never wipe. The hero just
            // keeps showing the previous value (or nothing).
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

    /// Resets the store to its pre-login defaults. Called from
    /// `RootView`'s state-transition handler when the user signs
    /// out / forgets the device / hits a session-expiry recovery
    /// path — so the next sign-in doesn't briefly show the
    /// previous account's task list.
    func clear() {
        stopAutoRefresh()
        activityController.end()
        tasks = []
        isLoading = false
        hasLoadedOnce = false
        isOnline = true
        errorMessage = nil
        freeDiskBytes = nil
        lastStorageFetch = nil
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Mutations
    //
    // Each action fires its client call and then re-fetches so the
    // local task array reflects the server's new state without
    // waiting for the next 5 s tick. Errors land in
    // `errorMessage` for view-level alerts.

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

    func stop(_ task: DownloadTask) async {
        do {
            try await client.stopTasks(ids: [task.id])
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

    func delete(_ task: DownloadTask, keepPartialFiles: Bool = false) async {
        do {
            try await client.deleteTask(id: task.id, keepPartialFiles: keepPartialFiles)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
extension DownloadTaskStore {
    /// Test-only factory that pre-populates `tasks` without going
    /// through the API client. Used by the view-model derivation
    /// tests so `DashboardViewModel.activeTransfers` etc. can be
    /// asserted against a known input without spinning up a real
    /// Synology session. Never call this from app code.
    static func makeForTesting(tasks: [DownloadTask]) -> DownloadTaskStore {
        let store = DownloadTaskStore(client: SynologyAPIClient())
        store.tasks = tasks
        store.hasLoadedOnce = true
        return store
    }
}
#endif
