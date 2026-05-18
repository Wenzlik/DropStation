import SwiftUI

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
