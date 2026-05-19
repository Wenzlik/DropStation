import SwiftUI

/// Inline row of pre-formatted metric strings separated by subtle
/// dot dividers — "3 active tasks · ↑ 3.2 MB/s · 1.2 TB free".
/// Designed for the hero card's tertiary metadata line and any
/// future surface that wants the same calm, dense data shape.
///
/// The caller pre-formats each value (so this component stays
/// domain-free and locale-free); DSMetricRow only enforces the
/// shared font, secondary tone, monospaced digits, and divider
/// styling.
struct DSMetricRow: View {
    private let values: [String]
    private let separator: String

    init(values: [String], separator: String = "·") {
        self.values = values
        self.separator = separator
    }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                if index > 0 {
                    Text(separator)
                        .foregroundStyle(.tertiary)
                }
                Text(value)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }
}
