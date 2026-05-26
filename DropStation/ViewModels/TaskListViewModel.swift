import Foundation
import SwiftUI
import Combine

/// View-local state for the Downloads tab. After the 0.5.1
/// `DownloadTaskStore` extraction, this viewmodel no longer owns
/// the `tasks` array or the polling timer — it derives the
/// `filteredTasks` slice from the shared store using its own
/// filter / sort / search state, which is intrinsically per-view
/// and survives across store refreshes.
///
/// Filter / sort / search live here; tasks / loading / mutations
/// live on the store. Mutation methods kept as passthroughs so
/// the view's swipe-action call sites read the same as before
/// the refactor (`viewModel.pause(task)` etc.).
@MainActor
final class TaskListViewModel: ObservableObject {
    @Published var filter: TaskFilter = .all
    @Published var searchText: String = ""
    @Published var sort: TaskSort = .dateAdded {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: TaskSortSettings.sortKey) }
    }
    @Published var sortDirection: TaskSortDirection = .descending {
        didSet { UserDefaults.standard.set(sortDirection.rawValue, forKey: TaskSortSettings.directionKey) }
    }

    private let store: DownloadTaskStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: DownloadTaskStore) {
        self.store = store
        // Restore sort preferences. didSet observers don't fire from init,
        // so the writes happen only on user changes — not on every launch.
        if let raw = UserDefaults.standard.string(forKey: TaskSortSettings.sortKey),
           let restored = TaskSort(rawValue: raw) {
            self.sort = restored
        }
        if let raw = UserDefaults.standard.string(forKey: TaskSortSettings.directionKey),
           let restored = TaskSortDirection(rawValue: raw) {
            self.sortDirection = restored
        }
        // Republish the store's change signal — the filtered list
        // depends on store.tasks, so view observers of this view
        // model need to recompute when the store ticks.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Store passthrough

    var tasks: [DownloadTask] { store.tasks }
    var isLoading: Bool { store.isLoading }
    var errorMessage: String? {
        get { store.errorMessage }
        set { store.errorMessage = newValue }
    }

    func refresh() async {
        await store.refresh()
    }

    // MARK: - Filter / sort / search derivation

    /// Tasks matching the current filter and (optionally) the search query,
    /// ordered by the chosen sort. Search uses `localizedStandardContains`
    /// so the match is case- and diacritic-insensitive.
    var filteredTasks: [DownloadTask] {
        var result = tasks.filter { filter.matches($0) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.title.localizedStandardContains(query) }
        }
        return result.sorted(by: sort, direction: sortDirection)
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

    // MARK: - Mutations (passthrough to the shared store)

    func createTask(uri: String, destination: String? = nil) async {
        await store.createTask(uri: uri, destination: destination)
    }

    func createTask(fileData: Data, filename: String, destination: String? = nil) async {
        await store.createTask(fileData: fileData, filename: filename, destination: destination)
    }

    func pause(_ task: DownloadTask) async {
        await store.pause(task)
    }

    func stop(_ task: DownloadTask) async {
        await store.stop(task)
    }

    func resume(_ task: DownloadTask) async {
        await store.resume(task)
    }

    func delete(_ task: DownloadTask, keepPartialFiles: Bool = false) async {
        await store.delete(task, keepPartialFiles: keepPartialFiles)
    }
}
