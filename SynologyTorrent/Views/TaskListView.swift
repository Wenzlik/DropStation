import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel: TaskListViewModel
    @State private var showingAddTask = false

    init(session: SessionStore) {
        _viewModel = StateObject(wrappedValue: TaskListViewModel(client: session.client))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.tasks) { task in
                    TaskRow(task: task)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(task) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .overlay {
                if viewModel.tasks.isEmpty, !viewModel.isLoading {
                    ContentUnavailableView("No downloads",
                                           systemImage: "arrow.down.circle",
                                           description: Text("Tap + to add a magnet or URL."))
                }
            }
            .refreshable { await viewModel.refresh() }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign out") {
                        Task { await session.logout() }
                    }
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
                AddTaskView { uri in
                    await viewModel.createTask(uri: uri)
                }
            }
            .task {
                // Reuse the shared client from SessionStore by binding it once.
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
}

private struct TaskRow: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title).font(.body).lineLimit(2)
            ProgressView(value: task.progress)
            HStack {
                Text(task.status.rawValue.capitalized)
                Spacer()
                Text(formattedSize(task.size))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
