import SwiftUI

/// Compact action chip used inside a row or grid of quick actions.
/// Renders an SF Symbol + label inside a Liquid Glass capsule.
/// Generic — the dashboard's "Add / Pause all / Resume all /
/// Search" row is the first user, but any screen that needs a
/// utility-feeling action grid (Settings shortcuts, detail-screen
/// action row, future server switcher) can reuse it.
///
/// Disabled state is supported via `isEnabled` and is purely
/// visual — actual gating is done at the call site so callers can
/// decide whether a placeholder action shows a "coming soon"
/// hint, a toast, or simply nothing.
struct DSQuickAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
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
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button {
            tapCount &+= 1
            action()
        } label: {
            VStack(spacing: DSSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isEnabled ? tint : Color.secondary)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.sm)
            .glassEffect(
                .regular,
                in: .rect(cornerRadius: DSRadius.tile, style: .continuous)
            )
            .opacity(isEnabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }
}
