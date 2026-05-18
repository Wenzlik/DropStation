import SwiftUI

/// Centered spinner with a localizable caption. Replaces ad-hoc
/// `ProgressView() + Text(...)` stacks scattered through the app.
struct DSLoadingView: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey = "Loading…") {
        self.title = title
    }

    var body: some View {
        VStack(spacing: DSSpacing.md) {
            ProgressView()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
