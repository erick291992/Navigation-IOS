import Foundation

/// Lightweight timing logger for picker perf investigation.
///
/// Two timestamps per event: total elapsed since first event, and delta
/// since previous event. Console output is the only sink. Compiled-out in
/// release builds AND gated by a runtime flag in debug builds (default OFF).
///
/// **Usage**:
/// 1. Set `PickerPerfLog.isEnabled = true` somewhere early (e.g. modifier
///    `.onAppear`, `App.init`) when you want to investigate.
/// 2. Call `reset(_:)` at the moment the picker is about to present so the
///    timeline starts at zero.
/// 3. `event(_:)` calls print `[elapsed +delta] name` lines to the console.
/// 4. Flip `isEnabled` back to `false` (or just delete the line) when done.
///
/// Call sites stay in the codebase so future investigations don't need to
/// re-instrument from scratch — search `PickerPerfLog.` to find them all.
public enum PickerPerfLog {
    /// Flip to `true` when investigating perf. Stays `false` in committed
    /// code so normal Debug builds have a clean console. Release builds
    /// don't compile the bodies at all (see `#if DEBUG`).
    public static var isEnabled = false

    private static var start: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private static var lastEvent: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private static let queue = DispatchQueue(label: "picker.perflog")

    /// Rate-limit per-cell `.task` logs so a 60-cell grid doesn't spam 180
    /// lines per session. Counter resets on `reset(_:)` (sheet present) and
    /// on `resetCellLogger()` (album switch).
    private static var cellLogCount = 0
    private static let cellLogLimit = 4

    public static func reset(_ label: String) {
        #if DEBUG
        guard isEnabled else { return }
        queue.sync {
            let now = CFAbsoluteTimeGetCurrent()
            start = now
            lastEvent = now
            cellLogCount = 0
            print("⏱ ── RESET: \(label) ──")
        }
        #endif
    }

    /// Reset only the per-cell log counter without resetting the timeline.
    /// Call this on album switch so the next ~4 cells of the new album log
    /// without breaking the cumulative session timeline.
    public static func resetCellLogger() {
        #if DEBUG
        guard isEnabled else { return }
        queue.sync { cellLogCount = 0 }
        #endif
    }

    /// Returns `true` if the calling cell should emit perf-log lines.
    /// Increments an internal counter; once `cellLogLimit` cells have
    /// logged within the current reset window, subsequent calls return
    /// `false` until the next reset. Thread-safe.
    public static func shouldLogCell() -> Bool {
        #if DEBUG
        guard isEnabled else { return false }
        return queue.sync {
            guard cellLogCount < cellLogLimit else { return false }
            cellLogCount += 1
            return true
        }
        #else
        return false
        #endif
    }

    public static func event(_ name: String) {
        #if DEBUG
        guard isEnabled else { return }
        queue.sync {
            let now = CFAbsoluteTimeGetCurrent()
            let totalMs = Int((now - start) * 1000)
            let deltaMs = Int((now - lastEvent) * 1000)
            lastEvent = now
            print("⏱ [\(String(format: "%5d", totalMs))ms  +\(String(format: "%4d", deltaMs))ms] \(name)")
        }
        #endif
    }
}
