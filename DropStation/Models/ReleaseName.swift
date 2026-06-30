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

        // Year = first standalone 19xx/20xx token (anywhere).
        let yearIndex = tokens.firstIndex(where: Self.isYear)

        // Title = the leading run of real words, stopping at the first
        // metadata token: a year, a quality tag, or "noise" (language
        // codes, channel/audio markers, bare numbers). Crucially this
        // cuts *before* the year too, so audio/lang junk that scene
        // names put ahead of the year
        // ("INTERSTELLAR-CZE.5.1.DD.ENG…2014") doesn't leak into the
        // title — that one resolves to just "INTERSTELLAR".
        var titleTokens: [String] = []
        for token in tokens {
            if Self.isYear(token) { break }
            if Self.tag(for: token) != nil { break }
            if let prefix = Self.wordPrefixBeforeNoise(token) {
                if !prefix.isEmpty { titleTokens.append(prefix) }
                break
            }
            if Self.isNoise(token) { break }
            titleTokens.append(token)
        }
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

    /// Language codes, audio markers, and channel/bitrate fragments
    /// that scene names sprinkle through the title region. Treated as
    /// a hard title boundary so they never show up as part of the name.
    private static let noiseWords: Set<String> = [
        "cze", "eng", "cz", "en", "ces", "sk", "ger", "fre", "spa", "ita",
        "rus", "pol", "hun", "kor", "jpn", "chs", "cht",
        "sub", "subs", "multi", "dual", "hardsub", "hc",
        "dd", "ddp", "eac3", "mp3", "flac", "lpcm", "dl",
    ]

    /// A token that should end the title: a bare number ("5", "1",
    /// "264"), a single character, or a known language/audio noise
    /// word. (Years are handled separately, before this is consulted.)
    private static func isNoise(_ token: String) -> Bool {
        let t = token.lowercased()
        if t.count <= 1 { return true }
        if Int(t) != nil { return true }
        return noiseWords.contains(t)
    }

    /// Handles a hyphen-joined token whose tail is metadata, e.g.
    /// "INTERSTELLAR-CZE" → keep "INTERSTELLAR" then stop the title.
    /// Returns nil when the token has no metadata tail (a real
    /// hyphenated word like "Spider-Man" or "January-October" stays
    /// whole), and "" when the token starts with metadata (contribute
    /// nothing, just stop).
    private static func wordPrefixBeforeNoise(_ token: String) -> String? {
        guard token.contains("-") else { return nil }
        let parts = token.split(separator: "-").map(String.init)
        guard parts.count >= 2,
              let cut = parts.firstIndex(where: { isNoise($0) || tag(for: $0) != nil || isYear($0) })
        else { return nil }
        return cut > 0 ? parts.prefix(cut).joined(separator: "-") : ""
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
