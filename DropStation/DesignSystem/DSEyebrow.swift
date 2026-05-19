import SwiftUI

/// Uppercase tracked-caption section label. Reads as a calm,
/// utility-app eyebrow ("RECENTLY COMPLETED", "QUICK ACTIONS")
/// rather than a heavy title — pairs with the wider Phase-3
/// move from glass-everywhere to material-and-hairline surfaces.
///
/// Optional leading SF Symbol for sections that benefit from a
/// glyph cue, and an optional trailing `accessory` slot for
/// affordances like "See all →". The accessory defaults to
/// `EmptyView`, so the common no-accessory call site stays a
/// single-line `DSEyebrow("…")`.
struct DSEyebrow<Accessory: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let accessory: Accessory

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer(minLength: DSSpacing.sm)
            accessory
        }
    }
}
