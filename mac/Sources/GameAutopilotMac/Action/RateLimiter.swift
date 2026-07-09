import Foundation

/// Sliding 60-second-window action cap. Mirrors core/RateLimiter.kt.
final class RateLimiter {
    var maxPerMinute: Int
    private var timestamps: [TimeInterval] = []
    private let lock = NSLock()

    init(maxPerMinute: Int) {
        self.maxPerMinute = maxPerMinute
    }

    @discardableResult
    func tryAcquire(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let windowStart = now - 60.0
        while let first = timestamps.first, first < windowStart {
            timestamps.removeFirst()
        }
        if timestamps.count >= max(maxPerMinute, 1) { return false }
        timestamps.append(now)
        return true
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        timestamps.removeAll()
    }
}
