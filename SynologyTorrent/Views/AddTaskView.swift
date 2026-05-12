import SwiftUI

struct AddTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @State private var uri: String = ""
    @State private var isSubmitting = false

    /// Closure invoked when the user confirms a URI to add.
    let onAdd: (String) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Download URI") {
                    TextField("magnet:?xt=… or https://…", text: $uri, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...10)
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
                    .disabled(uri.isEmpty || isSubmitting)
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
                    session.pendingMagnetLink = nil
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        await onAdd(uri)
        isSubmitting = false
        dismiss()
    }
}
