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

    public static func reset(_ label: String) {
        #if DEBUG
        guard isEnabled else { return }
        queue.sync {
            let now = CFAbsoluteTimeGetCurrent()
            start = now
            lastEvent = now
            print("⏱ ── RESET: \(label) ──")
        }
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
