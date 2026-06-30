import WidgetKit
import SwiftUI

/// Widget extension entry point. Only the downloads Live Activity for
/// now; home-screen widgets can join this bundle later.
@main
struct DropStationWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DownloadsLiveActivity()
    }
}
