import SwiftUI

/// Composite container for the Phase-3 grouped-section pattern:
/// optional uppercase tracked eyebrow header, a `.regularMaterial`
/// rounded card hosting the content, and optional helper text
/// rendered *outside* the card as small secondary caption text.
///
/// Mirrors what SwiftUI's `Form` `Section { ... } header: { ... }
/// footer: { ... }` gives by default, but in the Phase-3 visual
/// language — DSEyebrow header instead of `.title3.semibold`,
/// custom material surface instead of the system grouped
/// background, and the helper text deliberately sitting outside
/// the card so it reads as supplementary context rather than
/// chrome.
///
/// Rows compose freely inside the content closure. There's no
/// auto-inserted divider between rows — call sites that want
/// hairlines between rows insert `Divider().padding(.leading,
/// inset)` explicitly. Verbose but predictable; keeps
/// heterogeneous row types straightforward.
///
///     DSSectionCard("APPEARANCE") {
///         DSSettingsRow.picker(label: "Theme", selection: $mode,
///                              options: AppearanceMode.allCases,
///                              optionLabel: \.label)
///     }
///
///     DSSectionCard("PRIVACY",
///                   helperText: "Your SID is stored in the iOS
///                                Keychain so the app stays signed
///                                in across launches.") {
///         DSSettingsRow.toggle(label: "Remember session", isOn: $remember)
///     }
struct DSSectionCard<Content: View>: View {
    private let title: LocalizedStringKey?
    private let systemImage: String?
    private let helperText: LocalizedStringKey?
    private let content: Content

    init(
        _ title: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        helperText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.helperText = helperText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                DSEyebrow(title, systemImage: systemImage)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.sm)
            }
            cardSurface
            if let helperText {
                Text(helperText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.top, DSSpacing.sm)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// `.regularMaterial` rounded rectangle + 0.5 pt hairline
    /// border. Identical surface treatment to `DSCard(.secondary)`,
    /// but DSSectionCard manages it directly so the row content
    /// can bleed horizontally to the card edges (each row pads
    /// itself; the card has zero internal padding) — letting
    /// dividers run edge-to-edge or up to the row's own indent
    /// without negative-padding tricks.
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
        return VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5))
    }
}
