import SwiftUI

/// Phase-2 Dashboard. Composed of three stacked surfaces:
///
///   1. Hero card — NAS hostname + Online/Offline badge in the
///      header, primary content slot below it shows either current
///      transfer rates + active count, or a friendly idle message
///      when nothing is transferring. Free-disk row is conditional;
///      Phase 2 leaves it dormant (the view model returns `nil`)
///      until a follow-up wires `SYNO.FileStation.Info`.
///
///   2. Quick actions — compact 4-up grid (Add / Pause all /
///      Resume all / Search). Pause/Resume/Search are presented as
///      disabled chips for now; the brief asks for a redesigned
///      action row that no longer leads with a single dominant
///      CTA, but the underlying bulk endpoints aren't part of
///      Phase 2.
///
///   3. Recently completed — up to five rows in an activity-feed
///      shape (icon, title, secondary metadata). Visual hierarchy
///      polish lands in commit 2 of Phase 2.
///
/// Sits inside its own `NavigationStack` so sheets (Settings, Add
/// task) and any future pushed destinations stay scoped to this
/// tab. Polls its own `DashboardViewModel`; sharing a single task
/// store across tabs is on the 0.5 roadmap.
struct DashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel: DashboardViewModel
    @State private var showingAddTask = false
    @State private var showingSettings = false
    /// Bumped after each user-initiated pull-to-refresh completes.
    /// Drives a `.sensoryFeedback(.success)` so the gesture has a
    /// tactile completion cue. Kept separate from the 5 s timer
    /// poll so background refreshes don't fire haptics.
    @State private var pullRefreshCount = 0

    init(session: SessionStore) {
        _viewModel = StateObject(
            wrappedValue: DashboardViewModel(
                client: session.client,
                hostname: Self.displayHostname(from: session.config),
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
                        heroCard
                            .redacted(reason: viewModel.hasLoadedOnce ? [] : .placeholder)
                            .animation(.easeInOut(duration: 0.25), value: viewModel.isIdle)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isOnline)
                        quickActions
                        recentSection
                            .redacted(reason: viewModel.hasLoadedOnce ? [] : .placeholder)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.recentlyCompleted.map(\.id))
                    }
                    .padding(DSSpacing.lg)
                }
                .refreshable {
                    await viewModel.refresh()
                    pullRefreshCount &+= 1
                }
                .sensoryFeedback(.success, trigger: pullRefreshCount)
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

    // MARK: - Hero

    private var heroCard: some View {
        DSHeroCard {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundStyle(.tint)
                Text(viewModel.hostname)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.isOnline {
                    DSStatusBadge("Online", tint: .green, systemImage: "circle.fill")
                } else {
                    DSStatusBadge("Offline", tint: .orange, systemImage: "circle.fill")
                }
            }
        } primary: {
            if viewModel.isIdle {
                idlePrimary
            } else {
                activePrimary
            }
        }
    }

    private var idlePrimary: some View {
        HStack(alignment: .center, spacing: DSSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("All downloads completed")
                    .font(.title3.weight(.semibold))
                Text("NAS is idle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let bytes = viewModel.freeDiskBytes {
                    Text("\(formattedSize(bytes)) free")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
    }

    private var activePrimary: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.lg) {
                rateColumn(
                    label: "Download",
                    systemImage: "arrow.down",
                    tint: .blue,
                    bytes: viewModel.totalDownloadSpeed
                )
                rateColumn(
                    label: "Upload",
                    systemImage: "arrow.up",
                    tint: .orange,
                    bytes: viewModel.totalUploadSpeed
                )
            }
            HStack(spacing: DSSpacing.sm) {
                DSStatusBadge(
                    "\(viewModel.activeCount) active",
                    tint: .green,
                    systemImage: "bolt.fill"
                )
                if viewModel.failedCount > 0 {
                    DSStatusBadge(
                        "\(viewModel.failedCount) failed",
                        tint: .red,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }
                Spacer()
                if let bytes = viewModel.freeDiskBytes {
                    Text("\(formattedSize(bytes)) free")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rateColumn(
        label: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        bytes: Int64
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(formattedRate(bytes))
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        DSSection("Quick actions", systemImage: "bolt") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: 4),
                spacing: DSSpacing.md
            ) {
                DSQuickAction("Add", systemImage: "plus", tint: .accentColor) {
                    showingAddTask = true
                }
                DSQuickAction(
                    "Pause all",
                    systemImage: "pause.fill",
                    tint: .orange,
                    isEnabled: false
                ) { /* wired in a later iteration */ }
                DSQuickAction(
                    "Resume all",
                    systemImage: "play.fill",
                    tint: .green,
                    isEnabled: false
                ) { /* wired in a later iteration */ }
                DSQuickAction(
                    "Search",
                    systemImage: "magnifyingglass",
                    tint: .accentColor,
                    isEnabled: false
                ) { /* placeholder for 0.5 BT search */ }
            }
        }
    }

    // MARK: - Recently completed

    private var recentSection: some View {
        DSSection("Recently completed", systemImage: "checkmark.circle") {
            if !viewModel.hasLoadedOnce {
                // First load — show skeleton rows instead of the empty
                // state so the section reads as "loading" rather than
                // "we checked and there's nothing". The `.redacted`
                // modifier on the outer recentSection then paints
                // these grey.
                VStack(spacing: DSSpacing.sm) {
                    ForEach(0..<3, id: \.self) { _ in
                        DSCard(.primary) {
                            activityRow(for: .skeletonPlaceholder)
                        }
                    }
                }
            } else if viewModel.recentlyCompleted.isEmpty {
                DSCard(.primary) {
                    DSEmptyState(
                        title: "Nothing finished yet",
                        message: "Completed downloads will show up here.",
                        systemImage: "tray"
                    )
                }
            } else {
                VStack(spacing: DSSpacing.sm) {
                    ForEach(viewModel.recentlyCompleted) { task in
                        DSCard(.primary) {
                            activityRow(for: task)
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

    /// Best-effort display label for the configured NAS. Falls back
    /// to "NAS" if the host string is empty (shouldn't happen post-
    /// login but defends against an edge case where the config was
    /// cleared mid-flight). DSM model name (e.g. "DS920+") would
    /// require a `SYNO.FileStation.Info` call we haven't wired up.
    private static func displayHostname(from config: ServerConfig) -> String {
        let host = config.host.trimmingCharacters(in: .whitespaces)
        return host.isEmpty ? "NAS" : host
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

    // MARK: - Activity row composition

    /// Maps a `DownloadTask` onto the domain-free `DSActivityRow`.
    /// Keeps DesignSystem/ free of app-model dependencies while
    /// centralising the dashboard's row formatting in one place
    /// (so Phase 3.2's visual pass can tune metadata wording
    /// without touching DSActivityRow).
    private func activityRow(for task: DownloadTask) -> some View {
        DSActivityRow(
            title: task.title,
            metadata: metadataLine(for: task),
            iconSystemName: task.type.systemImage,
            iconTint: .accentColor
        )
    }

    /// "Completed 5m ago • 18.7 GB" when a completion timestamp is
    /// available; falls back to just the size string otherwise
    /// (older DSM builds occasionally omit `completed_time` for
    /// paused-at-100 % rows).
    private func metadataLine(for task: DownloadTask) -> String {
        let size = ByteCountFormatter.string(fromByteCount: task.size.value, countStyle: .file)
        guard let completed = completedDate(for: task) else { return size }
        let relative = Self.relativeFormatter.localizedString(for: completed, relativeTo: Date())
        return "Completed \(relative) • \(size)"
    }

    private func completedDate(for task: DownloadTask) -> Date? {
        guard let raw = task.additional?.detail?.completedTime?.value, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(raw))
    }

    /// Single shared RelativeDateTimeFormatter — instantiation is
    /// non-trivial and the same instance is safe to reuse on the
    /// main actor where these rows render.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

private extension DownloadTask {
    /// Sentinel task used only to feed `ActivityFeedRow` placeholder
    /// rows behind a `.redacted(.placeholder)` modifier during the
    /// first dashboard load. Never decoded from the wire and never
    /// observed by users with the redaction off; the title text
    /// just needs enough length for the placeholder bar to look
    /// right.
    static var skeletonPlaceholder: DownloadTask {
        DownloadTask(
            id: "skeleton",
            title: "Loading recently completed download",
            size: 0,
            status: .finished,
            type: .bt,
            username: nil,
            additional: nil
        )
    }
}
