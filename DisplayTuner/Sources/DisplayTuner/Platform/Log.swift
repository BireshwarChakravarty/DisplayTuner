import os

/// Unified logging. Watch it live with:
///
///     log stream --level debug --predicate 'subsystem == "app.displaytuner.DisplayTuner"'
enum Log {
    private static let subsystem = "app.displaytuner.DisplayTuner"

    static let ddc = Logger(subsystem: subsystem, category: "ddc")
    static let display = Logger(subsystem: subsystem, category: "display")
    static let apply = Logger(subsystem: subsystem, category: "apply")
}
