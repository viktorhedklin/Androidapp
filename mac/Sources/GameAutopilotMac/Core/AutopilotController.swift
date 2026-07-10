import AppKit
import CoreGraphics
import Foundation

enum AutopilotState: Equatable {
    case idle(note: String?)
    case ready
    case running(phase: LoopPhase, note: String?)
    case error(message: String)
}

/// Singleton orchestrator -- owns settings, capture, memory, profiles,
/// the active decision loop, and the state SwiftUI observes. Mirrors
/// core/AutopilotController.kt.
///
/// State-mutating methods are @MainActor (SwiftUI/@Published requires
/// updates to land on the main thread); buildSnapshot() deliberately is
/// NOT actor-isolated so the OCR/AX-tree/image-encoding work it does
/// doesn't run on the main actor and jank the menu-bar status item.
final class AutopilotController: ObservableObject {
    static let shared = AutopilotController()

    @Published private(set) var state: AutopilotState = .idle(note: nil)
    @Published private(set) var currentTarget: ScreenCapture.Target?
    @Published private(set) var currentProfile: TargetProfile?
    /// Transient hand-off slot: set right before opening the "targetSetup"
    /// Window scene so TargetSetupView knows which target it's setting up
    /// -- plain SwiftUI Window scenes have no built-in way to pass a value
    /// in, so this small piece of shared state fills that gap.
    @Published var pendingSetupTarget: ScreenCapture.Target?

    let settingsStore = SettingsStore()
    let profileStore = TargetProfileStore()
    private let capture = ScreenCapture()
    private let memoryStore = TargetMemoryStore()
    private let recent = ActionRing()
    private lazy var rate = RateLimiter(maxPerMinute: settingsStore.settings.maxActionsPerMinute)

    private var targetPID: pid_t?
    private var loop: DecisionLoop?
    private var loopTask: Task<Void, Never>?

    private init() {}

    // MARK: - Target selection

    @MainActor
    func selectTarget(_ target: ScreenCapture.Target, profile: TargetProfile) {
        currentTarget = target
        currentProfile = profile
        targetPID = target.bundleIdentifier.flatMap { bundleID in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.processIdentifier
        }
        rate.maxPerMinute = settingsStore.settings.maxActionsPerMinute
        rate.reset()
        recent.clear()
        Task { await capture.setTarget(target) }
        if state == .idle(note: nil) {
            state = .ready
        }
    }

    func memory(for bundleIdentifier: String) -> String {
        memoryStore.get(bundleIdentifier)
    }

    func resetMemory(for bundleIdentifier: String) {
        memoryStore.clear(bundleIdentifier)
    }

    // MARK: - Lifecycle

    @discardableResult
    @MainActor
    func start(apiKey: String) -> Bool {
        guard let target = currentTarget, let profile = currentProfile else {
            state = .error(message: "No target selected")
            return false
        }
        guard !apiKey.isEmpty else {
            state = .error(message: "API key not set")
            return false
        }
        guard Permissions.hasAccessibility() else {
            state = .error(message: "Accessibility permission not granted")
            return false
        }
        guard Permissions.hasScreenRecording() else {
            state = .error(message: "Screen Recording permission not granted")
            return false
        }
        if loopTask != nil { return true }

        let settings = settingsStore.settings
        rate.maxPerMinute = settings.maxActionsPerMinute
        let brain = BrainFactory.create(settings: settings, apiKey: apiKey)
        let bundleID = target.bundleIdentifier ?? ""
        let initialMemory = memoryStore.get(bundleID)
        let dispatcher = ActionDispatcher(targetBundleIdentifier: target.bundleIdentifier)
        let useMarks = settings.useSetOfMarks
        let pid = targetPID
        // Fullscreen targets fall back to display-based capture (see
        // ScreenCapture.captureImage), which genuinely shows whatever's on
        // screen including an interrupter; only window-path targets have
        // the stale/frozen-buffer blind spot DecisionLoop guards against.
        let isWindowPathCapture = target.windowID != nil

        let newLoop = DecisionLoop(
            takeSnapshot: { [weak self] in await self?.buildSnapshot(useMarks: useMarks, pid: pid) },
            brain: brain,
            dispatcher: dispatcher,
            recent: recent,
            rate: rate,
            baseTickIntervalMs: settings.tickIntervalMs,
            targetName: profile.displayName,
            targetBundleIdentifier: bundleID,
            targetPrompt: profile.composedPrompt,
            goalMode: profile.goalMode,
            onlyActOnTarget: settings.onlyActOnTarget,
            isWindowPathCapture: isWindowPathCapture,
            initialMemory: initialMemory,
            onMemoryUpdate: { [weak self] text in
                self?.memoryStore.set(bundleID, text: text)
            },
            onState: { [weak self] phase, note in
                await self?.updatePhase(phase, note)
            }
        )
        loop = newLoop
        state = .running(phase: .idle, note: nil)

        loopTask = Task { [weak self] in
            while true {
                guard let self, !Task.isCancelled else { break }
                // `loop` is only ever written from @MainActor methods
                // (start/stop/quit/updatePhase) -- read it the same way
                // rather than relying on this Task's inherited isolation,
                // which is harder to reason about with the [weak self]
                // capture.
                let currentLoop: DecisionLoop? = await MainActor.run { self.loop }
                guard let currentLoop else { break }
                let delayMs = await currentLoop.tick()
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: UInt64(max(50, delayMs)) * 1_000_000)
            }
        }
        Logger.i("Autopilot started for \(profile.displayName)")
        return true
    }

    @MainActor
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        loop = nil
        state = currentTarget != nil ? .ready : .idle(note: nil)
        Logger.i("Autopilot stopped")
    }

    @MainActor
    func quit() {
        stop()
        Task { await capture.clearTarget() }
        currentTarget = nil
        currentProfile = nil
        targetPID = nil
        state = .idle(note: nil)
        recent.clear()
        Logger.i("Autopilot quit")
    }

    @MainActor
    private func updatePhase(_ phase: LoopPhase, _ note: String?) {
        if phase == .completed {
            // Brain-reported goal completion (.playUntilComplete targets
            // only, see DecisionLoop/PromptBuilder) -- tear the loop down
            // the same way stop() does, but land on a distinct message
            // instead of a bare "Ready" so the user actually sees it
            // completed rather than it silently reverting to idle.
            loopTask?.cancel()
            loopTask = nil
            loop = nil
            state = .idle(note: note ?? "Goal complete!")
            Logger.i("Autopilot completed its goal")
            return
        }
        if case .running = state {
            state = .running(phase: phase, note: note)
        }
    }

    // MARK: - Snapshot building (off the main actor)

    private func buildSnapshot(useMarks: Bool, pid: pid_t?) async -> ScreenSnapshot? {
        guard let cgImage = await capture.captureImage() else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        let frontmostBundleID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

        let a11y: A11yReadResult = pid.map { AccessibilityReader.read(pid: $0) } ?? A11yReadResult(lines: [], clickables: [])
        let ocrResult = (try? OcrEngine.recognize(cgImage)) ?? OcrEngine.OcrResult(lines: [], boxes: [])

        let marks = useMarks
            ? CandidateExtractor.build(clickables: a11y.clickables, ocrBoxes: ocrResult.boxes, maxMarks: 80)
            : []

        let hash = PerceptualHash.dHash(cgImage)
        let imageToEncode = (useMarks && !marks.isEmpty) ? SetOfMarksOverlay.annotate(cgImage, marks: marks) : cgImage
        guard let base64 = ScreenshotEncoder.encode(imageToEncode) else { return nil }

        return ScreenSnapshot(
            width: width,
            height: height,
            frontmostBundleIdentifier: frontmostBundleID,
            ocrLines: ocrResult.lines,
            a11yLines: a11y.lines,
            marks: marks,
            screenshotBase64Jpeg: base64,
            perceptualHash: hash
        )
    }
}
