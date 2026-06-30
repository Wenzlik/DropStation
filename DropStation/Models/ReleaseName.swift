import Foundation

/// Turns an ugly scene/torrent filename into something a media app
/// would show: a clean title, an optional year, and a short ordered
/// list of quality tags (4K / HDR / Atmos / WEB-DL …).
///
///   "Dune.2021.2160p.WEB-DL.DD+5.1.Atmos.HDR.HEVC-DeDo"
///     → title "Dune", year "2021",
///       tags ["4K", "HDR", "WEB-DL", "HEVC", "Atmos"]
///
/// Pure value type, no SwiftUI — easy to unit-test and reuse. The
/// parse is deliberately forgiving: anything it doesn't recognise
/// just stays out of the tags, and a name with no year/quality
/// tokens (e.g. "Holiday clip.avi") falls back to its cleaned self
/// as the title with no tags.
struct ReleaseName: Equatable {
    let title: String
    let year: String?
    let tags: [String]

    init(parsing raw: String) {
        let cleaned = Self.stripExtension(raw)
        // Normalise separators to spaces so tokens are comparable,
        // but keep hyphens (WEB-DL, DTS-HD) and pluses (DD+).
        let spaced = cleaned
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let tokens = spaced
            .split(whereSeparator: { $0 == " " })
            .map(String.init)

        // Year = first standalone 19xx/20xx token. Title is whatever
        // precedes it; if there's no year, the title runs up to the
        // first recognised quality token instead.
        let yearIndex = tokens.firstIndex(where: Self.isYear)
        let firstTagIndex = tokens.firstIndex { Self.tag(for: $0) != nil }
        let titleEnd = yearIndex ?? firstTagIndex ?? tokens.count

        let titleTokens = Array(tokens.prefix(titleEnd))
        let rawTitle = titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        self.title = rawTitle.isEmpty ? spaced.trimmingCharacters(in: .whitespaces) : rawTitle
        self.year = yearIndex.map { tokens[$0] }

        // Collect recognised tags across ALL tokens, deduped, then
        // emit them in a stable display priority so a row's pills
        // read resolution → HDR → source → codec → audio.
        var found = Set<String>()
        for token in tokens {
            if let tag = Self.tag(for: token) { found.insert(tag) }
        }
        self.tags = Self.displayOrder.filter(found.contains)
    }

    // MARK: - Token classification

    private static func isYear(_ token: String) -> Bool {
        guard token.count == 4, let n = Int(token) else { return false }
        return (1900...2099).contains(n)
    }

    /// Maps a raw token onto a canonical display tag, or nil if the
    /// token isn't a recognised quality marker. Matched on a
    /// lowercased, hyphen/plus-trimmed form with `contains` so
    /// group-suffixed tokens ("HEVC-DeDo") and joined audio
    /// ("DD+5") still resolve.
    private static func tag(for token: String) -> String? {
        let t = token.lowercased()
        // Order matters: check the more specific keys first
        // (dts-hd before dts, hdr10/dovi before generic).
        if t.contains("2160p") || t == "4k" || t.contains("uhd") { return "4K" }
        if t.contains("1080p") { return "1080p" }
        if t.contains("720p") { return "720p" }
        if t.contains("dovi") || t == "dv" || t.contains("dolby.vision") { return "Dolby Vision" }
        if t.contains("hdr") { return "HDR" }
        if t.contains("remux") { return "REMUX" }
        if t.contains("bluray") || t.contains("blu-ray") || t.contains("bdrip") { return "BluRay" }
        if t.contains("web-dl") || t.contains("webdl") || t.contains("webrip") || t == "web" { return "WEB-DL" }
        if t.contains("hdtv") { return "HDTV" }
        if t.contains("amzn") { return "Amazon" }
        if t.contains("dsnp") { return "Disney+" }
        if t.contains("hevc") || t.contains("x265") || t.contains("h265") { return "HEVC" }
        if t.contains("x264") || t.contains("h264") || t.contains("avc") { return "H.264" }
        if t.contains("atmos") { return "Atmos" }
        if t.contains("truehd") { return "TrueHD" }
        if t.contains("dts-hd") || t.contains("dtshd") { return "DTS-HD" }
        if t.contains("dts") { return "DTS" }
        if t.hasPrefix("dd+") || t.hasPrefix("ddp") { return "DD+" }
        if t.contains("ac3") { return "AC3" }
        if t.contains("aac") { return "AAC" }
        return nil
    }

    /// Stable left-to-right priority for the pills on a row.
    private static let displayOrder = [
        "4K", "1080p", "720p",
        "Dolby Vision", "HDR",
        "REMUX", "BluRay", "WEB-DL", "HDTV", "Amazon", "Disney+",
        "HEVC", "H.264",
        "Atmos", "TrueHD", "DTS-HD", "DTS", "DD+", "AC3", "AAC",
    ]

    private static let videoExtensions: Set<String> = [
        "mkv", "mp4", "avi", "m4v", "ts", "wmv", "mov", "mpg", "mpeg", "flv",
    ]

    private static func stripExtension(_ raw: String) -> String {
        guard let dot = raw.lastIndex(of: ".") else { return raw }
        let ext = raw[raw.index(after: dot)...].lowercased()
        return videoExtensions.contains(ext) ? String(raw[..<dot]) : raw
    }
}
