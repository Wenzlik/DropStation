import SwiftUI

/// Surface style for `DSSection`. Top-level (not nested in
/// DSSection) so the no-accessory call site can stay generic-
/// free.
enum DSSectionStyle {
    /// SF Symbol + title in `.title3.semibold`. The pre-Phase-3
    /// look, kept for back-compat.
    case standard
    /// Uppercase tracked-caption header via `DSEyebrow`. The
    /// utility-app, "calm information density" look targeted by
    /// the Phase-3 redesign.
    case eyebrow
}

/// Titled section with two header styles and an optional
/// trailing accessory slot (e.g. "See all →").
///
/// The accessory defaults to `EmptyView`, so the common no-
/// accessory call site stays the same single-trailing-closure
/// shape it had before this refactor. Existing callers — which
/// pass nothing for `style` or `accessory` — keep the `.standard`
/// SF-Symbol-plus-title header and don't need to be touched.
struct DSSection<Content: View, Accessory: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let style: DSSectionStyle
    private let content: Content
    private let accessory: Accessory

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        style: DSSectionStyle = .standard,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            header
            content
        }
    }

    @ViewBuilder
    private var header: some View {
        switch style {
        case .standard:
            HStack(spacing: DSSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.tint)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: DSSpacing.sm)
                accessory
            }
        case .eyebrow:
            DSEyebrow(title, systemImage: systemImage) {
                accessory
            }
        }
    }
}
