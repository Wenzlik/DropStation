import SwiftUI

/// Titled section with a consistent header style. Composes with any
/// content (cards, lists, stat tiles). The title is `LocalizedStringKey`
/// so callers automatically get string extraction when 0.5.0 wires up
/// `Localizable.strings`.
struct DSSection<Content: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let content: Content

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(spacing: DSSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.tint)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            content
        }
    }
}
