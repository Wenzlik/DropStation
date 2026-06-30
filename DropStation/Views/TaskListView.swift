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

    init(session: SessionStore, store: DownloadTaskStore) {
        // 105 forwarding now lives on DownloadTaskStore — wired
        // once at app init — so this view model only carries the
        // view-local filter/sort/search state. `session` is kept
        // for the pendingMagnetLink observation downstream.
        _ = session
        _viewModel = StateObject(wrappedValue: TaskListViewModel(store: store))
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
                            TaskRow(task: task)
                            // Tap target without the system disclosure
                            // chevron — a zero-opacity link behind the
                            // card keeps it a clean media-style tile.
                            .background {
                                NavigationLink(value: task) { EmptyView() }
                                    .opacity(0)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: DSSpacing.xs, leading: DSSpacing.lg, bottom: DSSpacing.xs, trailing: DSSpacing.lg))
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
                .listStyle(.plain)
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
        // `.navigationTitle` takes the String overload here (the title
        // is computed, not a literal), which does NOT auto-localize —
        // that's why the title rendered as English "Downloads" inside
        // the Czech UI. Resolve through the catalog explicitly, and
        // compose the filtered variant from the localized base + the
        // (already-localized) filter label so we don't need a separate
        // "Downloads — %@" catalog entry.
        let base = String(localized: "Downloads")
        return viewModel.filter == .all ? base : "\(base) — \(viewModel.filter.label)"
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
        if hasSearch { return String(localized: "No matches") }
        if viewModel.filter == .all {
            return String(localized: "No downloads")
        }
        let bucket = viewModel.filter.label.lowercased()
        return String(localized: "No \(bucket) downloads")
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

/// One download as a calm media-style card. Instead of a dense table
/// row of raw scene text, each task reads like an entry in a media
/// app:
///
///   - A rounded status tile (colour + glyph, pulsing while live) as
///     the leading anchor.
///   - A clean parsed title + year (`ReleaseName` turns
///     "Dune.2021.2160p.WEB-DL…-DeDo" into "Dune  2021").
///   - Up to three quality pills (4K / HDR / Atmos …) — the at-a-glance
///     "what kind of file is this".
///   - A quiet footer: status · optional live ↓ speed · size, with a
///     progress sliver only while the task is actively transferring.
///
/// The card sits on `.regularMaterial` with a hairline, spaced from
/// its neighbours by the list-row insets, so the screen breathes.
private struct TaskRow: View {
    let task: DownloadTask

    private var release: ReleaseName { ReleaseName(parsing: task.title) }
    private var tint: Color { task.displayStatusTintRaw.tintColor }

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            statusTile
            VStack(alignment: .leading, spacing: 7) {
                titleLine
                if !release.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(release.tags.prefix(3), id: \.self) { TagPill(text: $0) }
                    }
                }
                footerLine
                if isLive {
                    DSProgressSliver(value: task.progress, tint: tint)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .strokeBorder(Color.dsSurfaceHairline, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
    }

    /// Leading status tile — a soft tinted rounded square with the
    /// status glyph, pulsing while actively transferring. Reads like
    /// a small poster/app tile and gives the row a confident anchor.
    private var statusTile: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: task.displayStatusTintRaw.statusSystemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: isLive)
            )
            .accessibilityHidden(true)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(release.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            if let year = release.year {
                Text(year)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// Quiet footer: status word, an optional live ↓ speed, and the
    /// total size on the trailing edge. Percent/ETA are intentionally
    /// dropped from the card — the sliver carries progress; the card
    /// stays calm.
    private var footerLine: some View {
        HStack(spacing: 6) {
            Text(task.displayStatusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let speed = liveSpeed, speed > 0 {
                Text("·").font(.caption).foregroundStyle(.tertiary)
                Text("↓ \(formattedSpeed(speed))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: DSSpacing.sm)
            Text(formattedSize(task.size.value))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// True for actively-transferring tasks — drives the pulsing tile,
    /// the inline ↓ speed, and the progress sliver. `.paused` is
    /// filtered out so paused transfers don't pulse.
    private var isLive: Bool {
        task.canPause && task.status != .paused
    }

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

/// Small quality chip ("4K", "HDR", "Atmos"). Resolution chips take
/// the accent, HDR/Dolby Vision an amber tint, everything else a
/// neutral fill — a little colour without turning the row into a
/// rainbow.
private struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(palette.fg)
            .background(Capsule(style: .continuous).fill(palette.bg))
    }

    private var palette: (fg: Color, bg: Color) {
        switch text {
        case "4K", "1080p", "720p":
            return (.accentColor, Color.accentColor.opacity(0.14))
        case "HDR", "Dolby Vision":
            return (.orange, Color.orange.opacity(0.16))
        default:
            return (Color.primary.opacity(0.7), Color.primary.opacity(0.07))
        }
    }
}
