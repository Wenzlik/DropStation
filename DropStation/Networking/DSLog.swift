import Foundation

/// Lightweight prefix-logger for auth / session flow tracing. Output goes
/// to the Xcode console via `print` — enough for the debugging we need
/// today without dragging in os.Logger or a third-party framework.
///
/// All calls are routed through one of the topic methods (`auth`,
/// `session`, `api`) so a future move to `os.log` / Logger subsystems
/// can swap the implementation in one place. The `#if DEBUG` guard
/// keeps these calls out of release builds; release-only diagnostics
/// (if we ever want them) should go through a different channel.
enum DSLog {
    #if DEBUG
    private static let enabled = true
    #else
    private static let enabled = false
    #endif

    static func auth(_ message: @autoclosure () -> String,
                     file: String = #fileID,
                     line: Int = #line) {
        guard enabled else { return }
        print("[ds.auth] \(message()) — \(file):\(line)")
    }

    static func session(_ message: @autoclosure () -> String,
                        file: String = #fileID,
                        line: Int = #line) {
        guard enabled else { return }
        print("[ds.session] \(message()) — \(file):\(line)")
    }

    static func api(_ message: @autoclosure () -> String,
                    file: String = #fileID,
                    line: Int = #line) {
        guard enabled else { return }
        print("[ds.api] \(message()) — \(file):\(line)")
    }
}

/// Redact a secret-ish string (SID, password, …) for log output. Keeps
/// the first 4 characters + length so we can tell sessions apart in
/// logs without dumping the full SID. Empty / very short values are
/// passed through as a literal `<empty>` / `<short>` marker.
func redact(_ s: String) -> String {
    guard s.count > 6 else { return s.isEmpty ? "<empty>" : "<short:\(s.count)>" }
    return "\(s.prefix(4))…(len=\(s.count))"
}
