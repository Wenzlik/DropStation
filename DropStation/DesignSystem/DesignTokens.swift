import SwiftUI
import UIKit

/// Design tokens for the DS* component layer. Phase-1 skeleton:
/// just enough to keep new dashboard surfaces from hardcoding
/// magic numbers. Expand in 0.5.0 as the design system matures.
enum DSSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum DSRadius {
    static let tile: CGFloat = 14
    static let card: CGFloat = 18
}

extension Color {
    /// Hairline border colour for `.secondary` surfaces (DSCard
    /// secondary, DSSectionCard, DSGroupedRows, DSQuickAction,
    /// login form fields). Dynamic per `UIUserInterfaceStyle`:
    ///
    ///   - **Dark mode** — `Color(.separator)` at 60 % alpha, the
    ///     original 0.5.0 value. Dark backgrounds already give
    ///     `.regularMaterial` cards enough contrast against the
    ///     background gradient.
    ///   - **Light mode** — bumped to 85 % alpha. The system
    ///     separator at 0.6 was too faint against
    ///     `.regularMaterial` on light backgrounds, making cards
    ///     blend into the surrounding gradient. The stronger
    ///     hairline gives light-mode cards a crisper edge
    ///     without resorting to shadows or a heavier border.
    ///
    /// Single source of truth for the surface hairline — change
    /// here and every DS* secondary surface picks it up.
    static let dsSurfaceHairline: Color = Color(uiColor: UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            return UIColor.separator.withAlphaComponent(0.6)
        default:
            return UIColor.separator.withAlphaComponent(0.85)
        }
    })
}
