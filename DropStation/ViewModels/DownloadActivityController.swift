import ActivityKit
import Foundation

/// Owns the single Live Activity for active downloads. The store hands
/// it the latest task list after every poll; it starts the activity
/// when something begins downloading, updates it as speeds/progress
/// move, and ends it when nothing is downloading any more.
///
/// All no-ops gracefully when Live Activities are disabled (Settings)
/// or unavailable, so callers never have to guard.
@MainActor
final class DownloadActivityController {
    private var activity: Activity<DownloadsActivityAttributes>?
    private let serverName: String

    init(serverName: String) {
        self.serverName = serverName
    }

    func sync(with tasks: [DownloadTask]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        let downloading = tasks.filter { $0.status == .downloading }
        guard !downloading.isEmpty else {
            end()
            return
        }

        // Lead = the fastest current download; it headlines the
        // compact/minimal presentations where there's only room for one.
        let lead = downloading.max {
            ($0.additional?.transfer?.speedDownload.value ?? 0)
                < ($1.additional?.transfer?.speedDownload.value ?? 0)
        } ?? downloading[0]
        let totalSpeed = downloading.reduce(Int64(0)) {
            $0 + ($1.additional?.transfer?.speedDownload.value ?? 0)
        }
        let state = DownloadsActivityAttributes.ContentState(
            activeCount: downloading.count,
            downloadSpeed: totalSpeed,
            topTitle: ReleaseName(parsing: lead.title).title,
            topProgress: lead.progress
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity {
            Task { await activity.update(content) }
        } else {
            activity = try? Activity.request(
                attributes: DownloadsActivityAttributes(serverName: serverName),
                content: content
            )
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
