import SwiftUI

/// Compact action chip used inside a row or grid of quick actions.
/// Icon-first, short label, monochrome by default — designed to
/// sit in a 2×2 grid of equal-weight actions without one dominant
/// CTA. Generic — the dashboard's quick-actions grid is the first
/// user, but any utility surface that needs an action chip (a
/// future Settings shortcut row, a per-server tile, etc.) can
/// reuse it.
///
/// Visual treatment (Phase-3 hierarchy): `.regularMaterial` +
/// half-point hairline border. No glass — quick action chips
/// shouldn't compete with the hero card for surface emphasis.
///
/// Two "not live" states:
///
///   - `isComingSoon: true` — keeps the chip visually intentional
///     (no opacity-dim) and surfaces a small uppercase "Soon"
///     badge in the corner. Communicates "planned feature" rather
///     than "disabled bug". The chip is still disabled and won't
///     fire its action; the badge is the user-facing reason.
///   - `isEnabled: false` — generic disabled state (caller decides
///     the reason). Falls back to a faded opacity look.
struct DSQuickAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let isComingSoon: Bool
    let action: () -> Void

    /// Counter bumped on every successful tap. Drives an internal
    /// `.sensoryFeedback(.impact)` so every caller gets a subtle
    /// haptic for free — keeps the action grid feeling tactile
    /// without each call site re-implementing the same modifier.
    @State private var tapCount: Int = 0

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        tint: Color = .accentColor,
        isEnabled: Bool = true,
        isComingSoon: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isEnabled = isEnabled
        self.isComingSoon = isComingSoon
        self.action = action
    }

    var body: some View {
        Button {
            tapCount &+= 1
            action()
        } label: {
            cell
        }
        .buttonStyle(DSQuickActionButtonStyle())
        .disabled(!isEnabled || isComingSoon)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }

    private var cell: some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.tile, style: .continuous)
        return VStack(spacing: DSSpacing.sm) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(effectiveTint)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.md)
        .padding(.horizontal, DSSpacing.sm)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(Color.dsSurfaceHairline, lineWidth: 0.5))
        .overlay(alignment: .topTrailing) {
            if isComingSoon {
                soonBadge
            }
        }
        // isComingSoon stays full opacity — the badge is the
        // communication channel, not a faded chrome. Generic
        // `isEnabled` false still dims so callers can express
        // genuinely unavailable states (e.g. "no pausable tasks
        // right now").
        .opacity(isEnabled || isComingSoon ? 1.0 : 0.55)
    }

    private var soonBadge: some View {
        Text("Soon")
            .font(.caption2.weight(.semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.separator).opacity(0.5), in: Capsule())
            .padding(DSSpacing.sm)
            .accessibilityLabel("Coming soon")
    }

    private var effectiveTint: Color {
        // Disabled actions fade their icon tint to secondary —
        // "coming soon" keeps the colour so the chip stays visually
        // present.
        if !isEnabled && !isComingSoon { return Color.secondary }
        return tint
    }
}

/// ButtonStyle wiring the pressed-scale interaction. SwiftUI's
/// `.buttonStyle(.plain)` doesn't expose the pressed state, so we
/// need a custom style to drive the `scaleEffect`. Kept private —
/// callers shouldn't reach for this directly; DSQuickAction
/// applies it for them.
private struct DSQuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
