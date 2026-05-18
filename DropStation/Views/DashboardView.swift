import SwiftUI

/// Phase-1 Dashboard. Glanceable stats + recently-completed +
/// quick-actions row. Sits inside its own `NavigationStack` so it
/// can present sheets (Settings, Add task) without interfering with
/// the Downloads tab's stack.
///
/// Polls its own `DashboardViewModel`; the list tab keeps its own
/// view model untouched. Sharing a single task store is on the
/// 0.5.0 roadmap, not Phase 1.
struct DashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel: DashboardViewModel
    @State private var showingAddTask = false
    @State private var showingSettings = false

    init(session: SessionStore) {
        _viewModel = StateObject(
            wrappedValue: DashboardViewModel(
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
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.xl) {
                        statsGrid
                        quickActions
                        recentSection
                    }
                    .padding(DSSpacing.lg)
                }
                .refreshable { await viewModel.refresh() }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
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
                AddTaskView(
                    onAddURI: { uri, destination in
                        await createTask(uri: uri, destination: destination)
                    },
                    onAddFile: { data, name, destination in
                        await createTask(fileData: data, filename: name, destination: destination)
                    }
                )
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
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
        }
    }

    // MARK: - Sections

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DSSpacing.md),
                GridItem(.flexible(), spacing: DSSpacing.md)
            ],
            spacing: DSSpacing.md
        ) {
            DSStatTile(
                title: "Active",
                value: "\(viewModel.activeCount)",
                systemImage: "bolt.circle",
                tint: .green
            )
            DSStatTile(
                title: "Failed",
                value: "\(viewModel.failedCount)",
                systemImage: "exclamationmark.triangle",
                tint: .red
            )
            DSStatTile(
                title: "Download",
                value: formattedRate(viewModel.totalDownloadSpeed),
                systemImage: "arrow.down",
                tint: .blue
            )
            DSStatTile(
                title: "Upload",
                value: formattedRate(viewModel.totalUploadSpeed),
                systemImage: "arrow.up",
                tint: .orange
            )
        }
    }

    private var quickActions: some View {
        DSSection("Quick actions", systemImage: "bolt") {
            DSCard {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Label("Add download", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Pause all / Resume all / Search coming in the next dashboard iteration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var recentSection: some View {
        DSSection("Recently completed", systemImage: "checkmark.circle") {
            if viewModel.recentlyCompleted.isEmpty {
                DSCard {
                    DSEmptyState(
                        title: "Nothing finished yet",
                        message: "Completed downloads will show up here.",
                        systemImage: "tray"
                    )
                }
            } else {
                VStack(spacing: DSSpacing.sm) {
                    ForEach(viewModel.recentlyCompleted) { task in
                        DSCard {
                            HStack(spacing: DSSpacing.md) {
                                Image(systemName: task.type.systemImage)
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    Text(formattedSize(task.size.value))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedRate(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else { return "0 KB/s" }
        return "\(ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .file))/s"
    }

    private func createTask(uri: String, destination: String?) async {
        do {
            try await session.client.createTask(uri: uri, destination: destination)
            await viewModel.refresh()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func createTask(fileData: Data, filename: String, destination: String?) async {
        do {
            try await session.client.createTask(fileData: fileData, filename: filename, destination: destination)
            await viewModel.refresh()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
