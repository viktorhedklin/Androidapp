import CoreGraphics
import Foundation

enum LoopPhase: Equatable {
    case idle
    case thinking
    case acting
    case error
    /// Signalled once by tick() when the brain reports goalComplete for a
    /// .playUntilComplete target. AutopilotController intercepts this and
    /// tears the loop down rather than displaying it as an ongoing phase.
    case completed
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
/// Interruption handling (ad redirects, accidental navigation to a
/// different app): when the target isn't frontmost, the tick is no
/// longer silently skipped -- the brain still runs and can reason about
/// recovery, bounded to `interruptionRecoveryTicks` consecutive ticks
/// before backing off to a slow, brain-free poll (see tick() for why:
/// removing the skip entirely would mean every tick while backgrounded
/// costs a paid LLM call and fights a user who deliberately switched
/// away). On window-path capture, the screenshot during an interruption
/// is stale/frozen (ScreenCaptureKit captures that window's own buffer
/// regardless of what's on top on screen), so click/keyboard-class
/// actions are rejected and stuck-hash bookkeeping is suppressed for
/// those ticks; on display-path (fullscreen) capture the screenshot
/// genuinely shows the interrupter, so no such restriction applies.
///
/// An actor rather than a plain class: serializes tick() automatically
/// (no hand-rolled locks needed for `memory`/stuck-state), driven by a
/// single external while-loop Task (see AutopilotController.start()).
actor DecisionLoop {
    static let stuckWindow = 3
    static let stuckDelta = 5
    static let stuckTrip = 6
    static let interruptionRecoveryTicks = 5
    static let interruptionBackoffMultiplier = 10

    private let takeSnapshot: () async -> ScreenSnapshot?
    private let brain: Brain
    private let dispatcher: ActionDispatcher
    private let recent: ActionRing
    private let rate: RateLimiter
    private let baseTickIntervalMs: Int
    private let targetName: String
    private let targetBundleIdentifier: String
    private let targetPrompt: String
    private let goalMode: GoalMode
    private let onlyActOnTarget: Bool
    private let isWindowPathCapture: Bool
    private let onMemoryUpdate: @Sendable (String) -> Void
    private let onState: @Sendable (LoopPhase, String?) async -> Void
    private let onCycle: @Sendable (CycleRecord) -> Void

    private var recentHashes: [UInt64] = []
    private var stuckCount = 0
    private var consecutiveNotFrontmostTicks = 0
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
        goalMode: GoalMode = .keepRunning,
        onlyActOnTarget: Bool,
        isWindowPathCapture: Bool,
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
        self.goalMode = goalMode
        self.onlyActOnTarget = onlyActOnTarget
        self.isWindowPathCapture = isWindowPathCapture
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

        // nil frontmost (couldn't determine) is treated as "don't block" --
        // matches the prior behavior's tolerance for a missing signal.
        let targetIsFrontmost = snapshot.frontmostBundleIdentifier.map { $0 == targetBundleIdentifier } ?? true
        let interrupted = onlyActOnTarget && !targetIsFrontmost

        consecutiveNotFrontmostTicks = interrupted ? consecutiveNotFrontmostTicks + 1 : 0

        if interrupted && consecutiveNotFrontmostTicks > Self.interruptionRecoveryTicks {
            // Bounded recovery window elapsed -- stop paying for brain
            // calls and stop trying to steal focus back; the user may
            // have deliberately switched away. Back off to a slow,
            // brain-free poll until frontmost naturally matches again.
            Logger.d("\(targetBundleIdentifier) not frontmost for \(consecutiveNotFrontmostTicks) ticks -- backing off")
            await onState(.idle, "Waiting for \(targetName)")
            return baseTickIntervalMs * Self.interruptionBackoffMultiplier
        }

        // A frozen/occluded window buffer during a window-path interruption
        // would produce identical hashes that falsely consume the stuck-
        // state trip budget before recovery gets a fair shot -- skip
        // stuck bookkeeping for those ticks specifically.
        let suppressStuckTracking = interrupted && isWindowPathCapture
        var delta = -1
        var stuckHint: String?
        if !suppressStuckTracking {
            delta = recentHashes.last.map { PerceptualHash.hamming($0, snapshot.perceptualHash) } ?? -1
            recordHash(snapshot.perceptualHash)
            if isStuck() {
                stuckCount += 1
                stuckHint = "screen has not changed across the last \(recentHashes.count) ticks -- try a different action."
            } else {
                stuckCount = 0
            }
            if stuckCount >= Self.stuckTrip {
                await onState(.error, "Stuck -- same screen \(stuckCount) ticks; pausing")
                stuckCount = 0
                return max(baseTickIntervalMs, 4_000)
            }
        }

        await onState(.thinking, nil)
        let ctx = BrainContext(
            targetName: targetName,
            targetBundleIdentifier: targetBundleIdentifier,
            targetPrompt: targetPrompt,
            goalMode: goalMode,
            screenWidth: snapshot.width,
            screenHeight: snapshot.height,
            screenshotBase64Jpeg: snapshot.screenshotBase64Jpeg,
            ocrLines: snapshot.ocrLines,
            a11yLines: snapshot.a11yLines,
            marks: snapshot.marks,
            recentActionLabels: recent.snapshot(),
            stuckHint: stuckHint,
            memory: memory,
            targetIsFrontmost: targetIsFrontmost
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

        if decision.goalComplete && goalMode == .playUntilComplete {
            let note = decision.thought.isEmpty ? "Goal complete!" : decision.thought
            await onState(.completed, note)
            onCycle(CycleRecord(snapshot: snapshot, thought: decision.thought, actionLabels: [], dispatchOk: [], deltaSincePrev: delta))
            return baseTickIntervalMs
        }

        if decision.actions.isEmpty {
            await onState(.idle, decision.thought.isEmpty ? "no actions" : decision.thought)
            onCycle(CycleRecord(snapshot: snapshot, thought: decision.thought, actionLabels: [], dispatchOk: [], deltaSincePrev: delta))
            return baseTickIntervalMs
        }

        await onState(.acting, String(decision.thought.prefix(80)))

        let bounds = CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
        // Within the bounded recovery window on window-path capture, the
        // screenshot is stale/frozen -- a click or keystroke can't safely
        // be aimed at anything, since we can't confirm what's actually
        // on screen. switchToTarget/wait/noop still pass (see
        // Action.requiresTargetFrontmost). Display-path capture genuinely
        // shows the interrupter, so no restriction applies there.
        let restrictToRecoveryActions = interrupted && isWindowPathCapture

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
            if restrictToRecoveryActions && action.requiresTargetFrontmost {
                Logger.w("Rejecting \(action.shortLabel) -- \(targetBundleIdentifier) not frontmost, window-path capture can't confirm what this would hit")
                labels.append(action.shortLabel + "(blocked:not-frontmost)")
                oks.append(false)
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
