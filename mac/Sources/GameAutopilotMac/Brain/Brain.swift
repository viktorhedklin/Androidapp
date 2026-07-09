import Foundation

protocol Brain {
    func decide(_ ctx: BrainContext) async throws -> BrainDecision
}

struct BrainContext {
    let targetName: String
    let targetBundleIdentifier: String
    let targetPrompt: String
    let screenWidth: Int
    let screenHeight: Int
    let screenshotBase64Jpeg: String
    let ocrLines: [String]
    let a11yLines: [String]
    let marks: [MarkBox]
    let recentActionLabels: [String]
    let stuckHint: String?
    /// Persistent per-target notes carried across ticks (and app restarts) -- see TargetMemoryStore.
    let memory: String
}

struct BrainDecision {
    let thought: String
    let actions: [Action]
    let confidence: Double
    /// Non-nil when the brain wants to replace `memory` for future ticks.
    let memoryUpdate: String?

    static let empty = BrainDecision(thought: "", actions: [], confidence: 0, memoryUpdate: nil)
}

struct BrainError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
    init(_ message: String) { self.message = message }
}
