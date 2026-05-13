import SwiftUI

struct TaskDetailView: View {
    @StateObject private var viewModel: TaskDetailViewModel
    @EnvironmentObject private var session: SessionStore

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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if viewModel.task.canPause {
                        Button {
                            Task { await viewModel.pause() }
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
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
                    .tint(viewModel.task.status.tintColor)
            }
            .padding(.vertical, 4)
        }
    }

    private var statusPill: some View {
        Text(viewModel.task.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(viewModel.task.status.tintColor.opacity(0.45)), in: .capsule)
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
            ForEach(files) { file in
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.filename ?? "(unnamed)").lineLimit(2).font(.subheadline)
                    HStack {
                        let down = file.sizeDownloaded?.value ?? 0
                        let total = file.size?.value ?? 0
                        Text("\(Self.bytes(down)) / \(Self.bytes(total))")
                        Spacer()
                        if let p = file.priority { Text(p.capitalized) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ProgressView(value: file.progress)
                }
                .padding(.vertical, 2)
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
                if let prio = d.priority { row("Priority", value: prio.capitalized) }
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
