import CoreGraphics
import Foundation

enum LoopPhase: Equatable {
    case idle
    case thinking
    case acting
    case error
}

struct CycleRecord {
    let snapshot: ScreenSnapshot
    let thought: String
    let actionLabels: [String]
    let dispatchOk: [Bool]
    let deltaSincePrev: Int
}

/// One tick = capture snapshot -> call brain -> dispatch returned actions.
/// Action.wait extends the delay BEFORE the next tick (it is not a
/// no-op) -- the single most important behavioral contract, mirrored
/// directly from DecisionLoop.kt.
///
/// Stuck-state guard: tracks the last `stuckWindow` perceptual hashes; if
/// Hamming distance is <= stuckDelta across all of them, asks the brain
/// for a recovery action with stuckHint set, then trips the loop into
/// .error after stuckTrip consecutive stuck ticks.
///
/// An actor rather than a plain class: serializes tick() automatically
/// (no hand-rolled locks needed for `memory`/stuck-state), driven by a
/// single external while-loop Task (see AutopilotController.start()).
actor DecisionLoop {
    static let stuckWindow = 3
    static let stuckDelta = 5
    static let stuckTrip = 6

    private let takeSnapshot: () async -> ScreenSnapshot?
    private let brain: Brain
    private let dispatcher: ActionDispatcher
    private let recent: ActionRing
    private let rate: RateLimiter
    private let baseTickIntervalMs: Int
    private let targetName: String
    private let targetBundleIdentifier: String
    private let targetPrompt: String
    private let onlyActOnTarget: Bool
    private let onMemoryUpdate: @Sendable (String) -> Void
    private let onState: @Sendable (LoopPhase, String?) async -> Void
    private let onCycle: @Sendable (CycleRecord) -> Void

    private var recentHashes: [UInt64] = []
    private var stuckCount = 0
    private var memory: String

    init(
        takeSnapshot: @escaping () async -> ScreenSnapshot?,
        brain: Brain,
        dispatcher: ActionDispatcher,
        recent: ActionRing,
        rate: RateLimiter,
        baseTickIntervalMs: Int,
        targetName: String,
        targetBundleIdentifier: String,
        targetPrompt: String,
        onlyActOnTarget: Bool,
        initialMemory: String = "",
        onMemoryUpdate: @escaping @Sendable (String) -> Void = { _ in },
        onState: @escaping @Sendable (LoopPhase, String?) async -> Void,
        onCycle: @escaping @Sendable (CycleRecord) -> Void = { _ in }
    ) {
        self.takeSnapshot = takeSnapshot
        self.brain = brain
        self.dispatcher = dispatcher
        self.recent = recent
        self.rate = rate
        self.baseTickIntervalMs = baseTickIntervalMs
        self.targetName = targetName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.targetPrompt = targetPrompt
        self.onlyActOnTarget = onlyActOnTarget
        self.memory = initialMemory
        self.onMemoryUpdate = onMemoryUpdate
        self.onState = onState
        self.onCycle = onCycle
    }

    /// Returns the delay (ms) before the next tick should run.
    func tick() async -> Int {
        guard let snapshot = await takeSnapshot() else {
            await onState(.idle, "No frame available")
            return baseTickIntervalMs
        }

        if onlyActOnTarget,
           let frontmost = snapshot.frontmostBundleIdentifier,
           frontmost != targetBundleIdentifier {
            Logger.d("Frontmost=\(frontmost), expected=\(targetBundleIdentifier) -- skipping tick")
            await onState(.idle, "Waiting for \(targetName)")
            return baseTickIntervalMs
        }

        let delta = recentHashes.last.map { PerceptualHash.hamming($0, snapshot.perceptualHash) } ?? -1
        recordHash(snapshot.perceptualHash)
        let stuck = isStuck()
        let stuckHint: String?
        if stuck {
            stuckCount += 1
            stuckHint = "screen has not changed across the last \(recentHashes.count) ticks -- try a different action."
        } else {
            stuckCount = 0
            stuckHint = nil
        }

        if stuckCount >= Self.stuckTrip {
            await onState(.error, "Stuck -- same screen \(stuckCount) ticks; pausing")
            stuckCount = 0
            return max(baseTickIntervalMs, 4_000)
        }

        await onState(.thinking, nil)
        let ctx = BrainContext(
            targetName: targetName,
            targetBundleIdentifier: targetBundleIdentifier,
            targetPrompt: targetPrompt,
            screenWidth: snapshot.width,
            screenHeight: snapshot.height,
            screenshotBase64Jpeg: snapshot.screenshotBase64Jpeg,
            ocrLines: snapshot.ocrLines,
            a11yLines: snapshot.a11yLines,
            marks: snapshot.marks,
            recentActionLabels: recent.snapshot(),
            stuckHint: stuckHint,
            memory: memory
        )

        let decision: BrainDecision
        do {
            decision = try await brain.decide(ctx)
        } catch {
            let message = (error as? BrainError)?.message ?? String(describing: error)
            Logger.e("Brain error: \(message)")
            await onState(.error, message)
            onCycle(CycleRecord(snapshot: snapshot, thought: "(brain error: \(message))", actionLabels: [], dispatchOk: [], deltaSincePrev: delta))
            return max(baseTickIntervalMs, 2_000)
        }

        if let newMemory = decision.memoryUpdate, newMemory != memory {
            memory = newMemory
            onMemoryUpdate(newMemory)
        }

        if decision.actions.isEmpty {
            await onState(.idle, decision.thought.isEmpty ? "no actions" : decision.thought)
            onCycle(CycleRecord(snapshot: snapshot, thought: decision.thought, actionLabels: [], dispatchOk: [], deltaSincePrev: delta))
            return baseTickIntervalMs
        }

        await onState(.acting, String(decision.thought.prefix(80)))

        let bounds = CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
        var extraWaitMs = 0
        var labels: [String] = []
        var oks: [Bool] = []
        for action in decision.actions {
            if case .wait(let ms) = action {
                extraWaitMs += ms
                labels.append(action.shortLabel)
                oks.append(true)
                continue
            }
            if case .noop = action {
                labels.append(action.shortLabel)
                oks.append(true)
                continue
            }
            guard rate.tryAcquire() else {
                Logger.w("Rate limit reached; skipping remaining actions this tick")
                break
            }
            let ok = await dispatcher.dispatch(action, marks: snapshot.marks, bounds: bounds)
            labels.append(action.shortLabel + (ok ? "" : "(fail)"))
            oks.append(ok)
            recent.add(action.shortLabel + (ok ? "" : "(fail)"))
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        onCycle(CycleRecord(snapshot: snapshot, thought: decision.thought, actionLabels: labels, dispatchOk: oks, deltaSincePrev: delta))

        return baseTickIntervalMs + extraWaitMs
    }

    private func recordHash(_ h: UInt64) {
        if recentHashes.count >= Self.stuckWindow { recentHashes.removeFirst() }
        recentHashes.append(h)
    }

    private func isStuck() -> Bool {
        guard recentHashes.count >= Self.stuckWindow, let first = recentHashes.first else { return false }
        return recentHashes.allSatisfy { PerceptualHash.hamming(first, $0) <= Self.stuckDelta }
    }
}
