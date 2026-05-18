import SwiftUI

/// Small colour-tinted capsule used to indicate state ("Online",
/// "Offline", "Idle", "Active"). Used by the dashboard hero, but
/// generic — any surface that wants a compact status indicator
/// can use it (Settings → server health, future per-server tiles,
/// etc.).
struct DSStatusBadge: View {
    let title: LocalizedStringKey
    let tint: Color
    let systemImage: String?

    init(_ title: LocalizedStringKey, tint: Color, systemImage: String? = nil) {
        self.title = title
        self.tint = tint
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 4)
        .glassEffect(
            .regular.tint(tint.opacity(0.18)),
            in: .capsule
        )
    }
}
