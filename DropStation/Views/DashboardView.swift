import SwiftUI

/// Post-login dashboard. Two stacked surfaces:
///
///   1. Hero card — NAS hostname + ambient status indicator in
///      the header. Primary slot dispatches on `heroState`:
///      `.transferring` shows the 44 pt focal speed + direction
///      arrow + live-pulse dot; `.taskIdle` shows the total task
///      count as the focal with a "Currently idle" subtitle;
///      `.empty` shows the calm "All caught up / No active
///      downloads" copy. Free-disk row is conditional on the
///      view-model placeholder (still nil pending the 0.5.1
///      SYNO.FileStation.Info wire-up).
///
///   2. Recently completed — up to five rows in an activity-feed
///      shape (icon disc, title, secondary metadata) inside a
///      single grouped material surface with hairline dividers
///      between rows. "See all →" accessory on the eyebrow header
///      drops the user into the Downloads tab with the `.finished`
///      filter pre-applied.
///
/// Add / Settings reachable via the toolbar `+` and gear. A
/// "Quick actions" section was prototyped in Phase 2 but
/// removed in 0.5.1 polish — three of the four planned actions
/// (Pause all / Resume all / Search) didn't have real backends
/// yet and disabled placeholders read as "coming soon" against
/// the rest of the modernised app. They return as the
/// DownloadTaskStore + bulk-action work lands.
///
/// Sits inside its own `NavigationStack` so sheets (Settings, Add
/// task) and pushed destinations stay scoped to this tab. Polls
/// its own `DashboardViewModel` for now; a shared
/// `DownloadTaskStore` is the next item up in 0.5.1.
struct DashboardView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: NavigationStore
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
                            .animation(.easeInOut(duration: 0.25), value: viewModel.heroState)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.isOnline)
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
            heroHeader
        } primary: {
            switch viewModel.heroState {
            case .transferring:
                activePrimary
            case .taskIdle:
                taskIdlePrimary
            case .empty:
                emptyPrimary
            }
        }
    }

    /// Hero header: drive glyph + hostname on the left, ambient
    /// status indicator on the right. Per the Phase-3 status
    /// hierarchy, Online is the ambient default (`DSStatusDot` +
    /// label) and only the exceptional Offline path bumps up to
    /// `DSStatusBadge`.
    private var heroHeader: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .foregroundStyle(.secondary)
            Text(viewModel.hostname)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            if viewModel.isOnline {
                HStack(spacing: 4) {
                    DSStatusDot(tint: .green)
                    Text("Online")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                DSStatusBadge("Offline", tint: .orange, systemImage: "circle.fill")
            }
        }
    }

    /// Empty hero (no tasks on the NAS at all). Pure T2 + T3
    /// typography, no T1 focal — a row of zeros would scream
    /// "broken", and an empty queue is supposed to feel calm.
    private var emptyPrimary: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("All caught up")
                .font(.headline.weight(.medium))
            Text("No active downloads")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !idleMetricValues.isEmpty {
                DSMetricRow(values: idleMetricValues)
                    .padding(.top, DSSpacing.xs)
            }
        }
    }

    /// Task-idle hero: queue exists but nothing is moving right
    /// now (paused, hash-checking, waiting, finished). Shows the
    /// total task count as the T1 focal so the dashboard still
    /// has a glanceable number rather than a 0 KB/s that would
    /// read as a frozen-bug state. Subtitle communicates the
    /// idleness explicitly.
    private var taskIdlePrimary: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                Text("\(viewModel.totalTaskCount)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(viewModel.totalTaskCount == 1 ? "Task" : "Tasks")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text("Currently idle")
                .font(.headline.weight(.medium))
                .foregroundStyle(.primary)
            if !taskIdleMetricValues.isEmpty {
                DSMetricRow(values: taskIdleMetricValues)
            }
            if viewModel.failedCount > 0 {
                DSStatusBadge(
                    "\(viewModel.failedCount) failed",
                    tint: .red,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .padding(.top, DSSpacing.xs)
            }
        }
    }

    /// Active hero: T1 focal speed number with optional live-pulse
    /// dot, T2 state title, T3 metric row. Failed count escalates
    /// to a `DSStatusBadge` (exceptional state) on its own row
    /// below.
    private var activePrimary: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            heroFocalRow
            Text(heroStateLabel)
                .font(.headline.weight(.medium))
                .foregroundStyle(.primary)
            if !activeMetricValues.isEmpty {
                DSMetricRow(values: activeMetricValues)
            }
            if viewModel.failedCount > 0 {
                DSStatusBadge(
                    "\(viewModel.failedCount) failed",
                    tint: .red,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .padding(.top, DSSpacing.xs)
            }
        }
    }

    /// T1 focal: large rounded monospaced rate + direction arrow,
    /// with a pulsing status dot when bytes are actively moving.
    /// `.contentTransition(.numericText())` ticks the digits as the
    /// poll updates so the number reads as live without bouncing.
    private var heroFocalRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Image(systemName: heroFocalDirectionSymbol)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(heroFocalTint)
            Text(formattedRate(heroFocalBytesPerSecond))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if heroIsActivelyTransferring {
                DSStatusDot(tint: heroFocalTint, pulsing: true)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Hero derived state

    /// Whether the NAS is currently moving bytes in either
    /// direction. Drives the pulsing focal dot.
    private var heroIsActivelyTransferring: Bool {
        viewModel.totalDownloadSpeed > 0 || viewModel.totalUploadSpeed > 0
    }

    /// Which direction "owns" the hero focal number. Download wins
    /// when present (it's the headline activity for a Download
    /// Station client); upload-only is the seeding-only case.
    /// Falls back to download (= 0) for the brief "1 active task
    /// hash-checking" window — viewModel.heroState has already
    /// shunted the everything-zero case to taskIdlePrimary or
    /// emptyPrimary, so this branch only runs when at least one
    /// direction is moving.
    private var heroFocalBytesPerSecond: Int64 {
        if viewModel.totalDownloadSpeed > 0 { return viewModel.totalDownloadSpeed }
        if viewModel.totalUploadSpeed > 0 { return viewModel.totalUploadSpeed }
        return viewModel.totalDownloadSpeed
    }

    private var heroFocalDirectionSymbol: String {
        viewModel.totalDownloadSpeed == 0 && viewModel.totalUploadSpeed > 0
            ? "arrow.up"
            : "arrow.down"
    }

    private var heroFocalTint: Color {
        viewModel.totalDownloadSpeed == 0 && viewModel.totalUploadSpeed > 0
            ? .accentColor
            : .blue
    }

    private var heroStateLabel: LocalizedStringKey {
        if viewModel.totalDownloadSpeed > 0 { return "Downloading" }
        if viewModel.totalUploadSpeed > 0 { return "Seeding" }
        return "Working…"
    }

    /// Tertiary metric line for the active hero. Pre-formats each
    /// fragment (count, opposite-direction rate, free disk) and
    /// hands it to `DSMetricRow` which renders them with the
    /// shared subtle-dot separators.
    private var activeMetricValues: [String] {
        var values: [String] = []
        if viewModel.activeCount > 0 {
            values.append("\(viewModel.activeCount) active")
        }
        // Show the opposite-direction rate inline when it's also
        // moving (download focal + upload trickle, or vice versa).
        if viewModel.totalDownloadSpeed > 0, viewModel.totalUploadSpeed > 0 {
            values.append("↑ \(formattedRate(viewModel.totalUploadSpeed))")
        }
        if let bytes = viewModel.freeDiskBytes {
            values.append("\(formattedSize(bytes)) free")
        }
        return values
    }

    private var idleMetricValues: [String] {
        var values: [String] = []
        if let bytes = viewModel.freeDiskBytes {
            values.append("\(formattedSize(bytes)) free")
        }
        return values
    }

    /// Tertiary metric line for the `.taskIdle` hero: how many of
    /// the tasks are paused vs. finished, plus free-disk when
    /// wired. Helps the user mental-model "what's the queue doing
    /// right now" beyond the single "X Tasks" focal number.
    private var taskIdleMetricValues: [String] {
        var values: [String] = []
        let pausedCount = viewModel.tasks.filter { TaskFilter.paused.matches($0) }.count
        let finishedCount = viewModel.tasks.filter { TaskFilter.finished.matches($0) }.count
        if pausedCount > 0 {
            values.append("\(pausedCount) paused")
        }
        if finishedCount > 0 {
            values.append("\(finishedCount) finished")
        }
        if let bytes = viewModel.freeDiskBytes {
            values.append("\(formattedSize(bytes)) free")
        }
        return values
    }

    // MARK: - Recently completed

    private var recentSection: some View {
        DSSection("Recently completed", style: .eyebrow) {
            recentSectionContent
        } accessory: {
            seeAllAccessory
        }
    }

    /// Trailing accessory on the Recently-completed eyebrow. Tap
    /// flips to the Downloads tab and stages a `.finished` filter
    /// via `NavigationStore`, which `TaskListView` consumes and
    /// clears in its `.onChange` handler. Hidden during first
    /// load — the slot reads as "scroll to nothing" otherwise.
    @ViewBuilder
    private var seeAllAccessory: some View {
        if viewModel.hasLoadedOnce, !viewModel.recentlyCompleted.isEmpty {
            Button {
                navigation.showDownloads(filter: .finished)
            } label: {
                HStack(spacing: 2) {
                    Text("See all")
                        .font(.caption.weight(.medium))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all completed downloads")
        }
    }

    @ViewBuilder
    private var recentSectionContent: some View {
        if !viewModel.hasLoadedOnce {
            // First load — three skeleton rows inside the grouped
            // container so the section reads as "loading" rather
            // than "we checked and there's nothing". The .redacted
            // modifier on the outer recentSection then paints
            // these grey.
            DSGroupedRows(
                Array(repeating: DownloadTask.skeletonPlaceholder, count: 3),
                dividerInset: activityRowDividerInset
            ) { task in
                activityRow(for: task)
            }
        } else if viewModel.recentlyCompleted.isEmpty {
            DSCard(.secondary) {
                DSEmptyState(
                    title: "Nothing finished yet",
                    message: "Completed downloads will show up here.",
                    systemImage: "tray"
                )
            }
        } else {
            DSGroupedRows(
                viewModel.recentlyCompleted,
                dividerInset: activityRowDividerInset
            ) { task in
                activityRow(for: task)
            }
        }
    }

    /// Aligns the hairline divider inside `DSGroupedRows` past the
    /// 36-pt icon disc that `DSActivityRow` draws — so each row's
    /// divider starts under its title text, not under its icon.
    /// Sum: disc width + DSActivityRow's internal disc-to-text gap
    /// + DSGroupedRows' container leading padding.
    private var activityRowDividerInset: CGFloat {
        36 + DSSpacing.md + DSSpacing.lg
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
