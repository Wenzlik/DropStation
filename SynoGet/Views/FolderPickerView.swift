import SwiftUI

/// Drill-down browser for the NAS shared folders + their subfolders.
/// Calls `onPick` with a FileStation path ("/Downloads/Movies") when the user taps
/// "Choose this folder" at any level, or with `nil` for "Default destination".
struct FolderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    let onPick: (FileNode?) -> Void

    @State private var rootShares: [FileNode] = []
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().controlSize(.large)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Cannot browse folders", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else {
                    List {
                        Section {
                            Button {
                                onPick(nil)
                                dismiss()
                            } label: {
                                Label("Default destination", systemImage: "folder")
                                    .foregroundStyle(.primary)
                            }
                        } footer: {
                            Text("Use the destination configured in DSM Download Station.")
                        }
                        Section("Shared folders") {
                            ForEach(rootShares) { share in
                                NavigationLink(value: share) {
                                    Label(share.name, systemImage: "externaldrive.connected.to.line.below")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: FileNode.self) { node in
                FolderBrowserLevel(folder: node) { picked in
                    onPick(picked)
                    dismiss()
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            rootShares = try await session.client.listShares()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// One level in the folder drill-down. Has its own [Use this folder] button at the top
/// so the user can stop at any depth.
private struct FolderBrowserLevel: View {
    @EnvironmentObject private var session: SessionStore
    let folder: FileNode
    let onPick: (FileNode) -> Void

    @State private var children: [FileNode] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        List {
            Section {
                Button {
                    onPick(folder)
                } label: {
                    Label("Use “\(folder.name)”", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            } footer: {
                Text(folder.path).font(.footnote).foregroundStyle(.secondary)
            }

            if isLoading {
                Section { ProgressView() }
            } else if let loadError {
                Section {
                    Text(loadError).foregroundStyle(.red).font(.footnote)
                    Button("Retry") { Task { await load() } }
                }
            } else if children.isEmpty {
                Section {
                    Text("No subfolders.").foregroundStyle(.secondary).font(.footnote)
                }
            } else {
                Section("Subfolders") {
                    ForEach(children) { sub in
                        NavigationLink(value: sub) {
                            Label(sub.name, systemImage: "folder")
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            children = try await session.client.listFolders(in: folder.path)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
