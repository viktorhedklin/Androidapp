import Foundation

/// Whether a target has a natural end state. Behaviorally load-bearing,
/// not cosmetic: "finish the full gameplay" has a terminal state the
/// brain should recognize and stop at; "spin these slots to gain level"
/// does not and should never self-report complete.
enum GoalMode: String, Codable {
    case playUntilComplete
    case keepRunning
}

/// Persisted per-target setup, replacing the bare "prompt" string used
/// before this: the researched understanding of the target plus the
/// user's explicit goal. Deliberately does NOT persist a Q&A transcript
/// -- that's setup-time scaffolding, not durable state; only what
/// actually feeds the live prompt is kept.
struct TargetProfile: Codable {
    let bundleIdentifier: String
    var displayName: String
    var userInfo: String
    var researchSummary: String
    var userGoal: String
    var goalMode: GoalMode
    var createdAt: Date
    var updatedAt: Date

    /// Condensed text fed into PromptBuilder every tick. Kept separate
    /// from the full research summary shown in the setup UI so a long
    /// grounded research blob doesn't inflate every single gameplay
    /// request's token cost -- this is deliberately short.
    var composedPrompt: String {
        var parts: [String] = []
        if !researchSummary.isEmpty { parts.append("Game knowledge: \(researchSummary)") }
        if !userGoal.isEmpty { parts.append("Goal: \(userGoal)") }
        return parts.joined(separator: "\n")
    }
}

/// Codable-JSON store keyed by bundle identifier, same on-disk convention
/// as TargetMemoryStore. Unlike TargetMemoryStore, this does NOT need an
/// NSLock: profiles are only ever read (AutopilotController.selectTarget)
/// and written (TargetSetupView) from @MainActor -- no DecisionLoop-actor
/// access exists for profiles the way it does for memory (memory is
/// written from inside the loop via onMemoryUpdate; profiles are fixed
/// for a run's duration once selectTarget composes the prompt). If a
/// future change makes DecisionLoop read profiles directly, revisit this.
final class TargetProfileStore {
    private var cache: [String: TargetProfile]
    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "com.gameautopilot.mac.profiles", qos: .utility)

    init() {
        let dir = Self.appSupportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("profiles.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: TargetProfile].self, from: data) {
            self.cache = decoded
        } else {
            self.cache = [:]
        }
    }

    func get(_ bundleIdentifier: String) -> TargetProfile? {
        cache[bundleIdentifier]
    }

    func save(_ profile: TargetProfile) {
        cache[profile.bundleIdentifier] = profile
        persist()
    }

    func clear(_ bundleIdentifier: String) {
        cache.removeValue(forKey: bundleIdentifier)
        persist()
    }

    private func persist() {
        let snapshot = cache
        let url = fileURL
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func appSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("GameAutopilotMac", isDirectory: true)
    }
}
