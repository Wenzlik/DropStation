import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity for active downloads — lock screen / banner plus the
/// Dynamic Island in its three presentations. Driven by
/// `DownloadsActivityAttributes` (shared with the app).
struct DownloadsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadsActivityAttributes.self) { context in
            lockScreen(context.state, server: context.attributes.serverName)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.activeCount)", systemImage: "arrow.down.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Self.speed(context.state.downloadSpeed))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.topTitle)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        ProgressView(value: context.state.topProgress)
                            .tint(.blue)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(Self.speed(context.state.downloadSpeed))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "dropstation://downloads"))
        }
    }

    @ViewBuilder
    private func lockScreen(_ state: DownloadsActivityAttributes.ContentState, server: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    // Single plural-aware key — the widget's own String
                    // Catalog supplies en (download/downloads) and cs
                    // ("stahování", invariant across counts).
                    Text("\(state.activeCount) downloads")
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                }
                Spacer()
                Text(Self.speed(state.downloadSpeed))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }
            Text(state.topTitle)
                .font(.headline)
                .lineLimit(1)
            ProgressView(value: state.topProgress)
                .tint(.blue)
        }
    }

    private static func speed(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else { return "0 KB/s" }
        return "\(ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .file))/s"
    }
}
