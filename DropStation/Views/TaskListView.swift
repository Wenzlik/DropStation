import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: NavigationStore
    @StateObject private var viewModel: TaskListViewModel
    @State private var showingAddTask = false
    @State private var showingSettings = false
    /// Task the user just swiped to delete; non-nil presents the
    /// keep-partial-files confirmation dialog.
    @State private var taskPendingDelete: DownloadTask?

    init(session: SessionStore) {
        // Forward 105s to the SessionStore so the host swaps in the
        // recovery card instead of just flashing an error banner.
        _viewModel = StateObject(
            wrappedValue: TaskListViewModel(
                client: session.client,
                onUnauthorized: { [weak session] reason in
                    Task { @MainActor in
                        session?.handleUnauthorized(reason: reason)
                    }
                }
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()
                List {
                    // Single grouped section — one rounded card on the screen,
                    // hairline dividers between rows (the DSGroupedRows visual
                    // pattern). `.swipeActions` and `.refreshable` aren't
                    // available outside List, so we keep List but drop the
                    // per-row glass and let `.insetGrouped` provide the
                    // chrome.
                    Section {
                        ForEach(viewModel.filteredTasks) { task in
                            NavigationLink(value: task) {
                                TaskRow(task: task)
                            }
                            .listRowSeparatorTint(Color(.separator).opacity(0.6))
                            .listRowInsets(EdgeInsets(top: DSSpacing.sm, leading: DSSpacing.md, bottom: DSSpacing.sm, trailing: DSSpacing.md))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    taskPendingDelete = task
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if task.canPause {
                                    Button {
                                        Task { await viewModel.pause(task) }
                                    } label: {
                                        Label("Pause", systemImage: "pause.fill")
                                    }
                                    .tint(.orange)
                                }
                                if task.canStop {
                                    Button {
                                        Task { await viewModel.stop(task) }
                                    } label: {
                                        Label("Stop", systemImage: "stop.fill")
                                    }
                                    .tint(.gray)
                                }
                                if task.canResume {
                                    Button {
                                        Task { await viewModel.resume(task) }
                                    } label: {
                                        Label("Resume", systemImage: "play.fill")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.refresh() }
                .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search downloads")
            }
            .overlay {
                if viewModel.filteredTasks.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        emptyStateTitle,
                        systemImage: emptyStateIcon,
                        description: Text(emptyStateMessage)
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationSubtitle(speedSubtitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                AddTaskView(
                    onAddURI: { uri, destination in
                        await viewModel.createTask(uri: uri, destination: destination)
                    },
                    onAddFile: { data, name, destination in
                        await viewModel.createTask(fileData: data, filename: name, destination: destination)
                    }
                )
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .navigationDestination(for: DownloadTask.self) { task in
                TaskDetailView(task: task, client: session.client)
            }
            .task {
                viewModel.startAutoRefresh()
                await viewModel.refresh()
            }
            .onDisappear { viewModel.stopAutoRefresh() }
            .onChange(of: session.pendingMagnetLink) { _, newValue in
                if newValue != nil {
                    showingAddTask = true
                }
            }
            .onChange(of: navigation.downloadsFilterRequest) { _, request in
                // One-shot hint from a sibling tab (e.g. the
                // dashboard's "See all →" link landing on Finished).
                // Apply, then clear so the next user-driven filter
                // change isn't overwritten on a re-render.
                if let request {
                    viewModel.filter = request
                    navigation.downloadsFilterRequest = nil
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .confirmationDialog(
                "Delete this download?",
                isPresented: .init(
                    get: { taskPendingDelete != nil },
                    set: { if !$0 { taskPendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: taskPendingDelete
            ) { task in
                Button("Delete task and files", role: .destructive) {
                    Task { await viewModel.delete(task, keepPartialFiles: false) }
                }
                Button("Delete task only (keep partial files)") {
                    Task { await viewModel.delete(task, keepPartialFiles: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { task in
                Text(task.title)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $viewModel.filter) {
                ForEach(TaskFilter.allCases) { f in
                    Label("\(f.label) (\(viewModel.count(for: f)))", systemImage: f.systemImage)
                        .tag(f)
                }
            }
        } label: {
            Image(systemName: viewModel.filter == .all
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private var sortMenu: some View {
        Menu {
            // Two nested pickers: criterion, then direction. Tapping the
            // currently-selected criterion is a no-op (Picker swallows it),
            // so the direction is exposed as its own toggle below.
            Picker("Sort by", selection: $viewModel.sort) {
                ForEach(TaskSort.allCases) { s in
                    Label(s.label, systemImage: s.systemImage).tag(s)
                }
            }
            Divider()
            Picker("Direction", selection: $viewModel.sortDirection) {
                ForEach(TaskSortDirection.allCases) { d in
                    Label(d.label, systemImage: d.systemImage).tag(d)
                }
            }
        } label: {
            Image(systemName: viewModel.sortDirection == .ascending
                  ? "arrow.up.arrow.down.circle"
                  : "arrow.up.arrow.down.circle.fill")
        }
    }

    private var navigationTitle: String {
        viewModel.filter == .all ? "Downloads" : "Downloads — \(viewModel.filter.label)"
    }

    private var speedSubtitle: String {
        let down = viewModel.totalDownloadSpeed
        let up = viewModel.totalUploadSpeed
        guard down > 0 || up > 0 else { return "" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "↓ \(f.string(fromByteCount: down))/s   ↑ \(f.string(fromByteCount: up))/s"
    }

    private var hasSearch: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyStateTitle: String {
        if hasSearch { return "No matches" }
        return viewModel.filter == .all
            ? "No downloads"
            : "No \(viewModel.filter.label.lowercased()) downloads"
    }

    private var emptyStateIcon: String {
        hasSearch ? "magnifyingglass" : viewModel.filter.systemImage
    }

    private var emptyStateMessage: String {
        if hasSearch { return "No downloads match \"\(viewModel.searchText)\"." }
        return viewModel.filter == .all
            ? "Tap + to add a magnet, URL, or .torrent file."
            : "Switch filter or pull down to refresh."
    }
}

/// Single row in the Downloads list. Visual hierarchy now matches the
/// Phase-3 design-system patterns:
///
///   - Title row: type glyph + the torrent / file name, two lines max
///     with middle truncation so "Movie.2026.2160p.HDR.x265-GROUP"
///     keeps both prefix and codec suffix visible when constrained.
///   - Metadata row: inline `DSStatusDot` + status label, optional
///     live ↓ speed, total size on the trailing edge. No more tinted
///     glass capsule — the dot reads as ambient signal next to its
///     label, sitting flush against the surrounding row content.
///   - Progress bar stays at full width here; 4.1.2 swaps it for
///     `DSProgressSliver` and hides it for completed tasks.
private struct TaskRow: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: task.type.systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            ProgressView(value: task.progress)
                .tint(task.displayStatusTintRaw.tintColor)
            HStack(spacing: DSSpacing.sm) {
                DSStatusDot(tint: task.displayStatusTintRaw.tintColor, pulsing: isLive)
                Text(task.displayStatusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                if let speed = liveSpeed, speed > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    Label(formattedSpeed(speed), systemImage: "arrow.down")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: DSSpacing.sm)
                Text(formattedSize(task.size.value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// True for actively-transferring tasks — drives the inline ↓ speed
    /// readout and the pulsing dot. `canPause` excludes finished and
    /// errored states; `.paused` is explicitly filtered so paused
    /// transfers don't pulse just because they're pause-capable.
    private var isLive: Bool {
        task.canPause && task.status != .paused
    }

    /// Show ↓ speed inline only when the task is actively transferring; otherwise it's noise.
    private var liveSpeed: Int64? {
        guard isLive else { return nil }
        return task.additional?.transfer?.speedDownload.value
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedSpeed(_ bytes: Int64) -> String {
        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))/s"
    }
}
