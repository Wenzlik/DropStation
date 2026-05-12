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
            List {
                ForEach(viewModel.filteredTasks) { task in
                    NavigationLink(value: task) {
                        TaskRow(task: task)
                    }
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
            .overlay {
                if viewModel.filteredTasks.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView(
                        emptyStateTitle,
                        systemImage: emptyStateIcon,
                        description: Text(emptyStateMessage)
                    )
                }
            }
            .refreshable { await viewModel.refresh() }
            .navigationTitle(navigationTitle)
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
            Text(task.title).font(.body).lineLimit(2)
            ProgressView(value: task.progress)
            HStack {
                StatusPill(status: task.status)
                Spacer()
                Text(formattedSize(task.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
            .glassEffect(.regular.tint(tintColor.opacity(0.45)), in: .capsule)
            .foregroundStyle(.primary)
    }

    private var tintColor: Color {
        switch status {
        case .downloading, .seeding, .extracting: return .green
        case .waiting, .hash_checking, .filehosting_waiting, .finishing: return .blue
        case .paused: return .orange
        case .finished: return .gray
        case .error: return .red
        case .unknown: return .gray
        }
    }
}
