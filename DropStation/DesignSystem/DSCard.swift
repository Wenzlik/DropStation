import SwiftUI

/// Generic Liquid Glass card container. Wraps arbitrary content with
/// the project's standard padding + corner radius so callers don't
/// re-implement the same `.glassEffect(...)` chain on every surface.
struct DSCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular,
                in: .rect(cornerRadius: DSRadius.card, style: .continuous)
            )
    }
}
