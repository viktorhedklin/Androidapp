import os

/// Thin wrapper over unified logging. Mirrors util/Logger.kt's shape.
/// View live output with: log stream --predicate 'subsystem == "com.gameautopilot.mac"'
enum Logger {
    private static let log = os.Logger(subsystem: "com.gameautopilot.mac", category: "Autopilot")

    static func d(_ msg: String) { log.debug("\(msg, privacy: .public)") }
    static func i(_ msg: String) { log.info("\(msg, privacy: .public)") }
    static func w(_ msg: String) { log.warning("\(msg, privacy: .public)") }
    static func e(_ msg: String) { log.error("\(msg, privacy: .public)") }
}
