import SwiftUI

/// Big-number tile for dashboards. Renders an icon, a primary
/// monospaced value (animated on change via `numericText`), and a
/// caption label. Designed to sit inside a grid of similar tiles.
struct DSStatTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular,
            in: .rect(cornerRadius: DSRadius.tile, style: .continuous)
        )
    }
}
