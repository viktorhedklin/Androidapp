import Foundation

/// Persists a small free-text "memory" per target -- the brain's own
/// notes about goal/progress/what-to-try-next, carried across ticks and
/// app restarts. Keyed by bundle identifier since v1 has no persistent
/// target "library" to hang an id off. Mirrors data/GameMemoryStore.kt.
///
/// `set` is called from inside DecisionLoop's actor (via
/// AutopilotController's onMemoryUpdate callback) while `get`/`clear` are
/// called from the UI (MainActor) -- genuinely concurrent access to the
/// same dictionary, so it needs its own lock rather than relying on
/// either caller's isolation.
final class TargetMemoryStore {
    private var cache: [String: String]
    private let fileURL: URL
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.gameautopilot.mac.memory", qos: .utility)

    private static let maxChars = 4000

    init() {
        let dir = Self.appSupportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("memory.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.cache = decoded
        } else {
            self.cache = [:]
        }
    }

    func get(_ bundleIdentifier: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return cache[bundleIdentifier] ?? ""
    }

    func set(_ bundleIdentifier: String, text: String) {
        lock.lock()
        cache[bundleIdentifier] = String(text.prefix(Self.maxChars))
        let snapshot = cache
        lock.unlock()
        persist(snapshot)
    }

    func clear(_ bundleIdentifier: String) {
        lock.lock()
        cache.removeValue(forKey: bundleIdentifier)
        let snapshot = cache
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ snapshot: [String: String]) {
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
