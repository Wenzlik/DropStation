import ActivityKit
import Foundation

/// Shared Live Activity contract between the app (which starts and
/// updates the activity) and the widget extension (which renders the
/// Dynamic Island / lock-screen UI). Compiled into BOTH targets, so it
/// must stay dependency-free beyond Foundation + ActivityKit.
struct DownloadsActivityAttributes: ActivityAttributes {
    /// Live, changing values pushed on every poll tick.
    public struct ContentState: Codable, Hashable {
        /// How many tasks are actively pulling bytes right now.
        var activeCount: Int
        /// Aggregate download throughput across those tasks (bytes/s).
        var downloadSpeed: Int64
        /// Clean title of the lead (fastest) download.
        var topTitle: String
        /// Progress of the lead download, 0...1.
        var topProgress: Double
    }

    /// Static for the life of the activity — the NAS this belongs to.
    var serverName: String
}
