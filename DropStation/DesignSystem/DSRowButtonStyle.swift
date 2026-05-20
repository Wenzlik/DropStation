import SwiftUI

/// Pressed-state `ButtonStyle` for grouped-list rows that navigate
/// elsewhere on tap. iOS's default List selection highlight is a
/// coarse gray overlay; this gives the row a quick opacity dim
/// matching the dashboard's activity-feed feel.
///
/// Applies to `NavigationLink` content too — `NavigationLink`
/// accepts `.buttonStyle(...)` from iOS 16+ and delegates its
/// label rendering to the supplied style while keeping its own
/// tap-to-navigate behaviour. Combined with the standard List
/// row separator and `.insetGrouped` chrome, this is the row
/// affordance used everywhere a tap drills into a detail screen.
///
/// Animation is deliberately short (0.12 s ease-out): long enough
/// to read as intentional feedback, short enough not to delay the
/// push transition.
struct DSRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
