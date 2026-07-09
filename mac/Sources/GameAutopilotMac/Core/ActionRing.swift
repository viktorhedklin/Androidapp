import Foundation

/// Fixed-capacity ring buffer of recent action labels shown to the brain
/// as "recent actions" context. Mirrors core/ActionRing.kt.
final class ActionRing {
    private let capacity: Int
    private var buffer: [String] = []
    private let lock = NSLock()

    init(capacity: Int = 12) {
        self.capacity = capacity
    }

    func add(_ label: String) {
        lock.lock(); defer { lock.unlock() }
        if buffer.count >= capacity { buffer.removeFirst() }
        buffer.append(label)
    }

    func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        buffer.removeAll()
    }
}
