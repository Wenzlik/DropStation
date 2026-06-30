import SwiftUI

/// Section header — sentence-case, no all-caps tracking. The iOS 26
/// redesign retired the editorial uppercase eyebrow
/// ("RECENTLY COMPLETED") that read as a 2019 template in favour of a
/// calm native-feeling header ("Recently completed"). One component,
/// so every surface that uses it — dashboard sections, the Settings
/// section cards, the login eyebrow — picks up the change at once.
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: DSSpacing.sm)
            accessory
        }
    }
}
