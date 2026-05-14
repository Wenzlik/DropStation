import SwiftUI

/// Confirmation-dialog-style picker for either a task-level (low/normal/high)
/// or per-file (skip + low/normal/high) priority. Presented via
/// `.confirmationDialog` so the modal layout is iOS-native.
///
/// The two variants are different enough (file priority has the Skip option,
/// task priority doesn't) that two view modifiers wrap the same dialog
/// machinery rather than one mega-picker.
extension View {
    func taskPriorityPicker(
        isPresented: Binding<Bool>,
        currentPriority: TaskPriority?,
        onPick: @escaping (TaskPriority) -> Void
    ) -> some View {
        confirmationDialog(
            "Set priority",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            ForEach(TaskPriority.allCases) { p in
                Button(label(for: p, current: currentPriority)) {
                    onPick(p)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Higher-priority tasks get bandwidth first. Synology applies the choice within Download Station's own queue rules.")
        }
    }

    func filePriorityPicker(
        isPresented: Binding<Bool>,
        currentPriority: FilePriority?,
        filename: String?,
        onPick: @escaping (FilePriority) -> Void
    ) -> some View {
        confirmationDialog(
            filename ?? "Set file priority",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            ForEach(FilePriority.allCases) { p in
                Button(label(for: p, current: currentPriority), role: p == .skip ? .destructive : nil) {
                    onPick(p)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose per-file priority for this BT torrent. Skip stops the file from downloading.")
        }
    }

    // Helpers — visible-checkmark formatting for the currently-selected option.

    private func label(for priority: TaskPriority, current: TaskPriority?) -> String {
        priority == current ? "✓ \(priority.label)" : priority.label
    }

    private func label(for priority: FilePriority, current: FilePriority?) -> String {
        priority == current ? "✓ \(priority.label)" : priority.label
    }
}
