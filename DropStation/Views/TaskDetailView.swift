import SwiftUI

struct TaskDetailView: View {
    @StateObject private var viewModel: TaskDetailViewModel
    @State private var showingTaskPriorityPicker = false
    /// File index whose priority picker is currently open (nil = closed).
    @State private var filePriorityFileIndex: Int?

    init(task: DownloadTask, client: SynologyAPIClient) {
        _viewModel = StateObject(wrappedValue: TaskDetailViewModel(task: task, client: client))
    }

    var body: some View {
        List {
            overviewSection
            transferSection
            if let files = viewModel.task.additional?.file?.filter({ $0.filename != nil }), !files.isEmpty {
                filesSection(files: files)
            }
            if let trackers = viewModel.task.additional?.tracker?.filter({ ($0.url ?? "").isEmpty == false }), !trackers.isEmpty {
                trackersSection(trackers: trackers)
            }
            sourceSection
        }
        .navigationTitle(viewModel.task.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Hide the menu entirely when there's nothing to do (e.g. an
            // .unknown status with neither canPause nor canResume) so the
            // ellipsis isn't a dead tap-target.
            if viewModel.task.canPause || viewModel.task.canStop || viewModel.task.canResume {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if viewModel.task.canPause {
                            Button {
                                Task { await viewModel.pause() }
                            } label: {
                                Label("Pause", systemImage: "pause.fill")
                            }
                        }
                        if viewModel.task.canStop {
                            Button {
                                Task { await viewModel.stop() }
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                        }
                        if viewModel.task.canResume {
                            Button {
                                Task { await viewModel.resume() }
                            } label: {
                                Label("Resume", systemImage: "play.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .refreshable { await viewModel.refresh() }
        .task {
            viewModel.startAutoRefresh()
            await viewModel.refresh()
        }
        .onDisappear { viewModel.stopAutoRefresh() }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .taskPriorityPicker(
            isPresented: $showingTaskPriorityPicker,
            currentPriority: currentTaskPriority
        ) { picked in
            Task { await viewModel.setTaskPriority(picked) }
        }
        .filePriorityPicker(
            isPresented: .init(
                get: { filePriorityFileIndex != nil },
                set: { if !$0 { filePriorityFileIndex = nil } }
            ),
            currentPriority: currentFilePriority,
            filename: currentFileFilename
        ) { picked in
            if let idx = filePriorityFileIndex {
                Task { await viewModel.setFilePriority(picked, fileIndex: idx) }
            }
        }
    }

    private var currentTaskPriority: TaskPriority? {
        guard let raw = viewModel.task.additional?.detail?.priority else { return nil }
        return TaskPriority(rawValue: raw.lowercased())
    }

    private var currentFilePriority: FilePriority? {
        guard let idx = filePriorityFileIndex,
              let files = viewModel.task.additional?.file,
              idx < files.count
        else { return nil }
        return FilePriority.from(rawPriority: files[idx].priority)
    }

    private var currentFileFilename: String? {
        guard let idx = filePriorityFileIndex,
              let files = viewModel.task.additional?.file,
              idx < files.count
        else { return nil }
        return files[idx].filename
    }

    // MARK: - Sections

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.task.type.systemImage)
                        .foregroundStyle(.tint)
                    Text(viewModel.task.title).font(.headline)
                }
                HStack {
                    statusPill
                    Spacer()
                    Text("\(Int(viewModel.task.progress * 100))%")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                ProgressView(value: viewModel.task.progress)
                    .tint(viewModel.task.displayStatusTintRaw.tintColor)
            }
            .padding(.vertical, 4)
        }
    }

    private var statusPill: some View {
        // Uses the task-aware display label + tint so paused-at-100 % shows as
        // "Ended" (grey) just like a true `.finished` status — see
        // DownloadTask.displayStatusLabel.
        Text(viewModel.task.displayStatusLabel)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(viewModel.task.displayStatusTintRaw.tintColor.opacity(0.45)), in: .capsule)
    }

    private var transferSection: some View {
        Section("Transfer") {
            row("Size", value: Self.bytes(viewModel.task.size.value))
            if let t = viewModel.task.additional?.transfer {
                let down = t.sizeDownloaded.value
                let up = t.sizeUploaded.value
                let sd = t.speedDownload.value
                row("Downloaded", value: Self.bytes(down))
                row("Uploaded", value: Self.bytes(up))
                row("↓ Speed", value: Self.bytesPerSecond(sd))
                row("↑ Speed", value: Self.bytesPerSecond(t.speedUpload.value))
                if down > 0 {
                    let ratio = Double(up) / Double(down)
                    row("Ratio", value: String(format: "%.2f", ratio))
                }
                if viewModel.task.status == .downloading, sd > 0 {
                    let remaining = max(0, viewModel.task.size.value - down)
                    let secs = Double(remaining) / Double(sd)
                    row("ETA", value: Self.duration(secs))
                }
            }
            if let d = viewModel.task.additional?.detail {
                if let peers = d.totalPeers { row("Peers", value: "\(peers.value) total") }
                if let s = d.connectedSeeders { row("Seeders", value: "\(s.value) connected") }
                if let l = d.connectedLeechers { row("Leechers", value: "\(l.value) connected") }
            }
        }
    }

    private func filesSection(files: [DownloadTask.Additional.TorrentFile]) -> some View {
        Section("Files (\(files.count))") {
            // We need the index alongside each file for the per-file priority
            // API. Synology returns files in stable torrent-order so positional
            // index in this array matches the BT info dictionary's order.
            ForEach(Array(files.enumerated()), id: \.element.id) { idx, file in
                Button {
                    filePriorityFileIndex = idx
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.filename ?? "(unnamed)")
                            .lineLimit(2)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        HStack {
                            let down = file.sizeDownloaded?.value ?? 0
                            let total = file.size?.value ?? 0
                            Text("\(Self.bytes(down)) / \(Self.bytes(total))")
                            Spacer()
                            if let p = file.priority { Text(p.capitalized) }
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ProgressView(value: file.progress)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func trackersSection(trackers: [DownloadTask.Additional.Tracker]) -> some View {
        Section("Trackers (\(trackers.count))") {
            ForEach(trackers) { tracker in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tracker.url ?? "").lineLimit(2).font(.subheadline.monospaced())
                    HStack {
                        if let s = tracker.status { Text(s) }
                        Spacer()
                        if let seeds = tracker.seeds, let peers = tracker.peers {
                            Text("\(seeds.value) seeds · \(peers.value) peers")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            row("Type", value: viewModel.task.type.rawValue.uppercased())
            if let owner = viewModel.task.username, !owner.isEmpty {
                row("Owner", value: owner)
            }
            if let d = viewModel.task.additional?.detail {
                if let dest = d.destination { row("Destination", value: dest) }
                if let prio = d.priority {
                    priorityRow(rawPriority: prio)
                }
                if let t = d.createTime {
                    let date = Date(timeIntervalSince1970: TimeInterval(t.value))
                    row("Created", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let uri = d.uri, !uri.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URI").font(.caption).foregroundStyle(.secondary)
                        Text(uri).font(.footnote.monospaced()).lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// Priority row — tappable for BT torrents (Synology's DS2 set-priority
    /// endpoint is BT-only). For HTTP/FTP/NZB it renders as plain text so the
    /// user doesn't tap into a dead-end picker.
    @ViewBuilder
    private func priorityRow(rawPriority: String) -> some View {
        let isBT = viewModel.task.type == .bt || viewModel.task.type == .magnet
        if isBT {
            Button {
                showingTaskPriorityPicker = true
            } label: {
                HStack {
                    Text("Priority").foregroundStyle(.primary)
                    Spacer()
                    Text(rawPriority.capitalized)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            row("Priority", value: rawPriority.capitalized)
        }
    }

    private func row(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value).monospacedDigit().contentTransition(.numericText())
        }
    }

    // MARK: - Formatters

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private static func bytesPerSecond(_ n: Int64) -> String {
        n > 0 ? "\(bytes(n))/s" : "—"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.day, .hour, .minute, .second]
        f.maximumUnitCount = 2
        return f.string(from: seconds) ?? "—"
    }
}
