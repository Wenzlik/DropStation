import SwiftUI

// Layout helpers for windows regular in both axes: iPad and iPhone
// Duo's inner display. Every non-hinged iPhone always has one compact
// axis (an iPhone Max in landscape is regular width, compact height),
// so none of this changes an iPhone layout. Never branch on the idiom:
// both Duo displays report `.phone`.

extension View {
    /// Caps the width and centres it on wide windows. Every iPhone
    /// layout keeps the full width it had — the frames collapse to
    /// `nil` (layout-neutral) there, so the view's identity doesn't
    /// change across a fold and no state is lost.
    func readableWidth() -> some View {
        modifier(ReadableWidth())
    }

    /// Keeps text and controls off regions the system reserves (iOS
    /// 27.1): iPhone Duo's side status column and the fold. Beside a
    /// pane it pads that edge; through a full-window screen it keeps
    /// the content on the larger side (`ReservedEdgeInsets`). Pads the
    /// safe area, so backgrounds still run to the edge.
    /// Changes nothing where the system reserves nothing, or before
    /// iOS 27.1 / on the Xcode 26 toolchain.
    /// `includingFold: false` avoids only occlusions (the status
    /// column) — for chrome like the tab bar whose panes handle the
    /// fold themselves.
    func avoidsReservedRegions(includingFold: Bool = true) -> some View {
        modifier(AvoidsReservedRegions(includingFold: includingFold))
    }
}

enum DSLayout {
    /// Readable column for forms and sheets on wide windows.
    static let readableWidth: CGFloat = 600

    /// The one wide-window rule, so it can't drift between screens.
    static func isWide(_ horizontal: UserInterfaceSizeClass?, _ vertical: UserInterfaceSizeClass?) -> Bool {
        horizontal == .regular && vertical == .regular
    }
}

/// Two panes side by side for wide windows. On iOS 27.1 the system's
/// split arrangement places them on either side of the fold; before
/// that (no hinged device exists) a plain HStack, which also serves
/// iPad.
struct SplitPanes<Primary: View, Secondary: View>: View {
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        // `ArrangementView` exists only in the iOS 27.1 SDK; the
        // compiler check keeps Xcode 26 (Swift 6.3, Xcode Cloud)
        // building, #available guards the runtime.
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            ArrangementView {
                primary.avoidsReservedRegions()
            } secondary: {
                secondary.avoidsReservedRegions()
            }
            .arrangementViewStyle(.split)
        } else {
            stack
        }
        #else
        stack
        #endif
    }

    private var stack: some View {
        HStack(spacing: 0) {
            primary.frame(minWidth: 320, maxWidth: 440)
            Divider().ignoresSafeArea()
            secondary.frame(maxWidth: .infinity)
        }
    }
}

private struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        let wide = DSLayout.isWide(horizontalSizeClass, verticalSizeClass)
        content
            .frame(maxWidth: wide ? DSLayout.readableWidth : nil)
            .frame(maxWidth: wide ? CGFloat.infinity : nil)
    }
}

private struct AvoidsReservedRegions: ViewModifier {
    let includingFold: Bool
    @State private var insets = ReservedEdgeInsets()

    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            // Measured outside the padding, so the padding never feeds
            // back into the measurement. Active regions only (default
            // query options).
            content
                .safeAreaPadding(EdgeInsets(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing))
                .onGeometryChange(for: ReservedEdgeInsets.self) { proxy in
                    let regions = proxy.reservedRegions(kind: .occlusion)
                        + (includingFold ? proxy.reservedRegions(kind: .division) : [])
                    let safe = proxy.safeAreaInsets
                    return ReservedEdgeInsets(avoiding: regions.map(\.frame), in: proxy.size)
                        .beyond(ReservedEdgeInsets(top: safe.top, leading: safe.leading, bottom: safe.bottom, trailing: safe.trailing))
                } action: { newInsets in
                    insets = newInsets
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
