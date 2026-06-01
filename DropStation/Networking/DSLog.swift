import Foundation
import os

/// Prefix-logger for auth / session / api flow tracing. Dual sink:
///
///   - **os.Logger (unified logging)** — always on, including
///     Release / TestFlight builds. Viewable live in Console.app
///     (filter on subsystem `com.wenzlik.DropStation`) and captured
///     in a sysdiagnose, so session-lifecycle decisions — SID
///     preserved vs. wiped, which probe path fired, certificate
///     trust routing — are diagnosable on a real device, not just
///     in an Xcode debug run. This is the "release diagnostics
///     channel" the earlier print-only implementation deferred,
///     and it's what makes a field-reported session-persistence
///     issue investigable from a tester's sysdiagnose.
///   - **print** — DEBUG only, for the Xcode console during
///     development (unchanged from before).
///
/// Messages are pre-redacted at the call site (`redact(_:)` for
/// SIDs; cookie *values* are never logged, only metadata), so the
/// os.Logger lines are emitted `.public`. Without `.public` the
/// unified log shows `<private>` for the whole interpolated string
/// in Release and the diagnostics would be worthless. Never pass
/// an unredacted secret to DSLog — it now reaches the persistent
/// unified log, not just a transient debug console.
enum DSLog {
    private static let subsystem = "com.wenzlik.DropStation"
    private static let authLogger = Logger(subsystem: subsystem, category: "auth")
    private static let sessionLogger = Logger(subsystem: subsystem, category: "session")
    private static let apiLogger = Logger(subsystem: subsystem, category: "api")

    #if DEBUG
    private static let consoleEnabled = true
    #else
    private static let consoleEnabled = false
    #endif

    static func auth(_ message: @autoclosure () -> String,
                     file: String = #fileID,
                     line: Int = #line) {
        emit(message(), logger: authLogger, tag: "ds.auth", file: file, line: line)
    }

    static func session(_ message: @autoclosure () -> String,
                        file: String = #fileID,
                        line: Int = #line) {
        emit(message(), logger: sessionLogger, tag: "ds.session", file: file, line: line)
    }

    static func api(_ message: @autoclosure () -> String,
                    file: String = #fileID,
                    line: Int = #line) {
        emit(message(), logger: apiLogger, tag: "ds.api", file: file, line: line)
    }

    private static func emit(_ message: String,
                             logger: Logger,
                             tag: String,
                             file: String,
                             line: Int) {
        // `.default` level so the line persists in the unified log
        // store (retrievable via sysdiagnose), not just live in
        // Console. These calls are low-frequency (auth/session
        // lifecycle, not the 5 s poll), so the always-on cost is
        // negligible.
        logger.log("\(message, privacy: .public) — \(file, privacy: .public):\(line)")
        if consoleEnabled {
            print("[\(tag)] \(message) — \(file):\(line)")
        }
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
