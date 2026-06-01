import Foundation

/// Task-level priority on Synology Download Station.
/// DSM lists `auto` as a default state for new BT tasks; only low/normal/high
/// are explicitly settable via DS2 `Task.BT` `method=set`. We decode any
/// raw value (including "auto") for display but the user-settable picker
/// shows only the three real options.
enum TaskPriority: String, CaseIterable, Identifiable, Codable {
    case low
    case normal
    case high

    var id: String { rawValue }
    var label: String {
        switch self {
        case .low:    return String(localized: "Low")
        case .normal: return String(localized: "Normal")
        case .high:   return String(localized: "High")
        }
    }
}

/// Per-file priority inside a BT torrent. Skip is modelled here too — at
/// the API level it's `wanted=false` rather than a `priority` value, but
/// it's a single picker choice from the user's point of view.
enum FilePriority: String, CaseIterable, Identifiable {
    case skip
    case low
    case normal
    case high

    var id: String { rawValue }
    var label: String {
        switch self {
        case .skip:   return String(localized: "Skip (don't download)")
        case .low:    return String(localized: "Low")
        case .normal: return String(localized: "Normal")
        case .high:   return String(localized: "High")
        }
    }
    var systemImage: String {
        switch self {
        case .skip:   return "nosign"
        case .low:    return "tortoise"
        case .normal: return "equal.circle"
        case .high:   return "hare"
        }
    }

    /// `wanted` flag in the DS2 BT.File set payload. Skip is the only value
    /// where wanted is false; the rest opt the file into downloading and
    /// pick the relative priority.
    var wanted: Bool { self != .skip }

    /// Settable task priority that DS2 BT.File accepts (only when `wanted`).
    /// Skip has no underlying TaskPriority because the file isn't downloading.
    var taskPriority: TaskPriority? {
        switch self {
        case .skip:   return nil
        case .low:    return .low
        case .normal: return .normal
        case .high:   return .high
        }
    }

    /// Decode a TorrentFile's `priority` string (and missing-state) into one
    /// of our four cases. The API returns "skip" / "low" / "normal" / "high"
    /// (or the file may simply have wanted=false reflected as priority="skip"
    /// in `additional=file` responses).
    static func from(rawPriority: String?) -> FilePriority {
        switch rawPriority?.lowercased() {
        case "skip": return .skip
        case "low":  return .low
        case "high": return .high
        default:     return .normal
        }
    }

    /// `wanted`-aware resolver. Some DSM builds keep the file's pre-skip
    /// priority value ("normal", "low", …) in the `priority` field even
    /// after the user toggles `wanted=false` — so trusting only
    /// `rawPriority` produces a row that still reads as "Normal" while the
    /// file is no longer downloading. When `wanted == false` we collapse
    /// the result to `.skip` regardless of what `rawPriority` says, which
    /// matches DSM's actual behaviour (the file is not being pulled).
    static func from(rawPriority: String?, wanted: Bool?) -> FilePriority {
        if wanted == false { return .skip }
        return from(rawPriority: rawPriority)
    }
}
