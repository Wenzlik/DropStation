import SwiftUI

/// 2-point-tall tinted progress bar — a thin sliver, not a full
/// `ProgressView` slab. Designed to sit under a row's metadata line
/// as ambient progress signal rather than a dominant visual feature
/// (the giant green progress bars of legacy torrent-app rows).
///
/// Behaviour:
///   - `value` clamped to 0...1 so a stray Synology field can't push
///     the fill past the track.
///   - Track uses `Color(.separator)` at 40 % so it's barely visible
///     when value is small but still implies "this is a track".
///   - Fill uses the caller's `tint`, typically the row's status
///     colour (`DownloadTask.displayStatusTintRaw.tintColor`).
///   - `.animation` left to the caller — a list row already moves
///     when its containing row updates; we don't want to fight
///     SwiftUI's implicit list animations.
///
/// Callers usually wrap in an `if !task.isFinished` so completed
/// rows don't carry a redundant 100 %-filled bar; that decision is
/// the caller's because "finished" means different things on
/// different surfaces (dashboard activity row vs. downloads list).
struct DSProgressSliver: View {
    let value: Double
    let tint: Color
    /// Track + fill height. 2 pt by default — denser than the
    /// 4-ish-point standard ProgressView, matching the "ambient
    /// signal" intent.
    let height: CGFloat

    init(value: Double, tint: Color = .accentColor, height: CGFloat = 2) {
        self.value = value
        self.tint = tint
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(value, 0), 1)
            let width = proxy.size.width * clamped
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(.separator).opacity(0.4))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
