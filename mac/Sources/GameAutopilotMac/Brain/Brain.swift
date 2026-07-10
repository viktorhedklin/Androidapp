import Foundation

protocol Brain {
    func decide(_ ctx: BrainContext) async throws -> BrainDecision
}

struct BrainContext {
    let targetName: String
    let targetBundleIdentifier: String
    let targetPrompt: String
    let goalMode: GoalMode
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
    /// False when a different app is currently frontmost (an ad redirect,
    /// accidental navigation, or the user deliberately switched away).
    /// See DecisionLoop's bounded-recovery handling.
    let targetIsFrontmost: Bool
}

struct BrainDecision {
    let thought: String
    let actions: [Action]
    let confidence: Double
    /// Non-nil when the brain wants to replace `memory` for future ticks.
    let memoryUpdate: String?
    /// True when the brain believes the target's goal has been reached.
    /// Only meaningful when the target's goalMode is .playUntilComplete --
    /// PromptBuilder instructs the brain to never set this for .keepRunning
    /// targets, which have no completion state by definition.
    let goalComplete: Bool

    static let empty = BrainDecision(thought: "", actions: [], confidence: 0, memoryUpdate: nil, goalComplete: false)
}

/// LocalizedError, not just CustomStringConvertible: conforming to
/// CustomStringConvertible alone does NOT make `.localizedDescription`
/// use `message` -- that's a different mechanism, and the default
/// Error.localizedDescription would otherwise print a generic
/// "operation couldn't be completed" string instead.
struct BrainError: Error, CustomStringConvertible, LocalizedError {
    let message: String
    var description: String { message }
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
