import SwiftUI
import UniformTypeIdentifiers

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var mode: Mode = .uri
    @State private var uri: String = ""
    @State private var pickedFile: PickedFile?
    @State private var isFileImporterPresented = false
    @State private var isSubmitting = false
    @State private var fileImportError: String?

    /// Callback for URI-based downloads.
    let onAddURI: (String) async -> Void
    /// Callback for file-based downloads.
    let onAddFile: (Data, String) async -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case uri = "Link"
        case file = "File"
        var id: String { rawValue }
    }

    struct PickedFile: Equatable {
        let name: String
        let data: Data
        let sizeDescription: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch mode {
                case .uri:
                    Section("Download URI") {
                        TextField("magnet:?xt=… or https://…", text: $uri, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(3...10)
                    }
                case .file:
                    Section("Torrent file") {
                        if let picked = pickedFile {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading) {
                                    Text(picked.name).lineLimit(1)
                                    Text(picked.sizeDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Change") {
                                    isFileImporterPresented = true
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Button {
                                isFileImporterPresented = true
                            } label: {
                                Label("Choose .torrent file…", systemImage: "folder")
                            }
                        }

                        if let fileImportError {
                            Text(fileImportError).foregroundStyle(.red).font(.caption)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Add download")
                        }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
            .navigationTitle("New download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let pending = session.pendingMagnetLink {
                    uri = pending
                    mode = .uri
                    session.pendingMagnetLink = nil
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: AddTaskView.allowedFileTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .uri: return !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file: return pickedFile != nil
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        switch mode {
        case .uri:
            await onAddURI(uri.trimmingCharacters(in: .whitespacesAndNewlines))
        case .file:
            guard let picked = pickedFile else { return }
            await onAddFile(picked.data, picked.name)
        }
        dismiss()
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        fileImportError = nil
        switch result {
        case .failure(let error):
            fileImportError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            // Files picked through .fileImporter return security-scoped URLs.
            // Without start/stop access the Data(contentsOf:) read fails with a permission error.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pickedFile = PickedFile(
                    name: url.lastPathComponent,
                    data: data,
                    sizeDescription: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                )
            } catch {
                fileImportError = error.localizedDescription
            }
        }
    }

    private static let allowedFileTypes: [UTType] = {
        var types: [UTType] = [.data]
        if let torrent = UTType(filenameExtension: "torrent") { types.insert(torrent, at: 0) }
        if let nzb = UTType(filenameExtension: "nzb") { types.append(nzb) }
        return types
    }()
}
