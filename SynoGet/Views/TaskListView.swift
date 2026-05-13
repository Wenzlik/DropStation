import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel: TaskListViewModel
    @State private var showingAddTask = false
    @State private var showingSettings = false

    init(session: SessionStore) {
        _viewModel = StateObject(wrappedValue: TaskListViewModel(client: session.client))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()
                List {
                    ForEach(viewModel.filteredTasks) { task in
                        NavigationLink(value: task) {
                            TaskRow(task: task)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
                                .contentShape(.rect(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(task) }
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.refresh() }
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
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
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

    private var emptyStateTitle: String {
        viewModel.filter == .all ? "No downloads" : "No \(viewModel.filter.label.lowercased()) downloads"
    }

    private var emptyStateIcon: String {
        viewModel.filter.systemImage
    }

    private var emptyStateMessage: String {
        viewModel.filter == .all
            ? "Tap + to add a magnet, URL, or .torrent file."
            : "Switch filter or pull down to refresh."
    }
}

private struct TaskRow: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: task.type.systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(task.title).font(.body).lineLimit(2)
            }
            ProgressView(value: task.progress)
                .tint(task.status.tintColor)
            HStack(spacing: 8) {
                StatusPill(status: task.status)
                if let speed = liveSpeed, speed > 0 {
                    Label(formattedSpeed(speed), systemImage: "arrow.down")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                Text(formattedSize(task.size.value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    /// Show ↓ speed inline only for tasks that are actively transferring; otherwise it's noise.
    private var liveSpeed: Int64? {
        guard task.canPause, task.status != .paused else { return nil }
        return task.additional?.transfer?.speedDownload.value
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedSpeed(_ bytes: Int64) -> String {
        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))/s"
    }
}

/// Compact status indicator rendered as a tinted Liquid Glass capsule.
private struct StatusPill: View {
    let status: DownloadTask.Status

    var body: some View {
        Text(status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(status.tintColor.opacity(0.45)), in: .capsule)
            .foregroundStyle(.primary)
    }
}
