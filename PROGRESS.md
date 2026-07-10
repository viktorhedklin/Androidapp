# Build Progress — Game Autopilot

Shared status log for this rebuild. Read this file first in any new
session before touching the repo. Full plan/rationale is at
`/root/.claude/plans/a-generic-no-root-android-purring-bee.md` (may not
be reachable from a different container — this file is the durable copy).

## Architecture (LLM-brain version, not JSON-rules)

The autopilot is an AI brain that watches the screen via MediaProjection
+ accessibility + ML Kit OCR, calls a cloud LLM (OpenAI-compatible:
OpenAI, NVIDIA NIM, any compatible vision model — or Google Gemini via
its own `generateContent` REST brain), and dispatches taps / swipes /
waits via accessibility gestures. A persistent overlay sits on top of
the running game with Start / Stop / Quit. Per-game knowledge lives in
each game's system prompt plus a small persistent per-game **memory**
(goal/progress notes the brain writes itself), stored in a small game
library.

User flow: open app → game library → tap "+" to add a game (pick app,
name, system prompt, tick rate) → Settings to set API key + model →
tap a game's "Launch & Autopilot" → permission check → overlay foreground
service starts → MediaProjection consent → game launches → tap Start in
the overlay → DecisionLoop runs: capture → think → act → wait.

## Status table

| Batch | Description | Status | Commit |
|------|------------------------------------------------|--------|---------|
| A | Foundation + UI shell (deps, manifest, all resources) | done | dbc4b0e |
| B | Data + brain (Game, Settings repos; OpenAI-compatible brain; core/Action) | done | 77f4573 |
| C | Capture + accessibility + core loop (ScreenCaptureManager, ML Kit OCR, AccessibilityService, GestureDispatcher, DecisionLoop, AutopilotController) | done | 0845eee |
| D | UI + overlay + wiring (Activities, GameListAdapter, OverlayService) | done | f0a5fb5 |
| E | README + verification pass | done | 0770aef |
| F | Set-of-marks + TypeText + stuck-state + cycle log | done | 4740b3d |
| G | Debug overlay + a11y fast path | **wip** | 3c9c1d1 (unpushed — see below) |
| H | Reasoner/ScreenReader/ActionExecutor interface refactor | not done | - |
| I | Gemini provider + persistent per-game memory | done | 625302b |
| - | Review-driven fixes (backup exclusions, dead code, privacy doc) | done | 694609a |
| - | Gradle wrapper files + GitHub Actions APK build workflow | done | (this commit) |

**Next batch: finish G, then H.**

## Gradle wrapper was missing (fixed 2026-07-06)

The repo had `gradle/wrapper/gradle-wrapper.properties` but **not**
`gradlew`, `gradlew.bat`, or `gradle-wrapper.jar` — an oversight from the
original Batch A scaffold. This meant `./gradlew` (as documented in the
README) never actually worked, locally or in CI. Regenerated via
`gradle wrapper --gradle-version 8.7 --distribution-type bin` (had to run
with `--offline` in this sandbox since the distribution-URL validation
network call is blocked by this environment's GitHub-scoped proxy — not
an issue for real CI runners or local dev machines, which have normal
internet access). Also added `.github/workflows/build-apk.yml`
(`workflow_dispatch` + push to `main`/this branch) to build the debug
APK on GitHub's runners and upload it as a downloadable artifact, since
this sandbox has no Android SDK and can't build/verify an APK directly.

## Push access note (resolved 2026-07-06)

Was blocked earlier the same day — `alpha666c` (the GitHub identity this
session pushes as) had read but not write access to
`viktorhedklin/Androidapp`. Fixed once the repo owner added `alpha666c`
as a collaborator with Write role. All commits through the macOS port
below pushed successfully after that — no longer an issue, leaving this
note only so a future session understands why earlier commits mention
push failures.

## Batch I — Gemini provider + persistent per-game memory (done)

**Gemini provider:**
- `brain/PromptBuilder.kt` (new) + `brain/BrainResponseParser.kt` (new) +
  `brain/CallAwait.kt` (new) — extracted the system/user prompt text and
  the strict-JSON response parsing out of `OpenAiCompatibleBrain` so both
  it and the new `GeminiBrain` share identical prompt/schema logic; only
  the HTTP envelope differs per provider.
- `brain/GeminiBrain.kt` (new) — calls Gemini's `generateContent` REST
  endpoint (`system_instruction` + `contents[].parts[]` with
  `inline_data` base64 image, `generationConfig.responseMimeType =
  "application/json"`), auth via `x-goog-api-key` header. Reports
  `promptFeedback.blockReason` in the exception when Gemini blocks a
  response instead of just failing opaquely.
- `data/Settings.kt` — `useNvidia: Boolean` replaced with
  `provider: BrainProvider` (`OPENAI`/`NVIDIA`/`GEMINI` enum) plus
  `defaultUrlFor`/`defaultModelFor` helpers. Default Gemini model is
  `gemini-3.5-flash` (GA as of mid-2026, vision-capable, supports
  Computer Use) — **not** `gemini-3.5-pro`, which per Google's own
  materials is scheduled to ship ~2026-07-17 and doesn't exist yet as an
  API model id. Once it (or any newer model) ships, just paste its model
  id into Settings → Model — no code change needed.
- `data/SettingsRepository.kt` — persists `provider` as a string enum
  name instead of the old boolean pref key.
- `ui/SettingsActivity.kt` + `res/layout/activity_settings.xml` — the
  provider toggle became a 3-way `RadioGroup` (OpenAI / NVIDIA NIM /
  Google Gemini) since a boolean switch no longer fits 3 options.
- `brain/BrainFactory.kt` — branches on `settings.provider`.

**Persistent per-game memory:**
- `brain/Brain.kt` — `BrainContext.gameMemory: String` (fed into the
  prompt each tick) and `BrainDecision.memoryUpdate: String?` (brain
  writes back an updated summary when something worth remembering
  happened — current goal, progress, what to try next).
- `data/GameMemoryStore.kt` (new) — one small text file per game at
  `filesDir/memory/{gameId}.txt`, capped at 4000 chars.
- `core/DecisionLoop.kt` — constructor gained `initialMemory` +
  `onMemoryUpdate`; keeps memory in a `@Volatile var`, includes it in
  every `BrainContext`, and calls back out when the brain updates it.
- `core/AutopilotController.kt` — loads memory from `GameMemoryStore` in
  `start()`, persists updates via the loop's callback (fire-and-forget
  `scope.launch`). Memory intentionally survives `stop()`/`quit()` — the
  whole point is that it persists across sessions.
- `ui/AddGameActivity.kt` + `activity_add_game.xml` — **Reset memory**
  button (visible only when editing an existing game), separate from
  **Delete**. Deleting a game also clears its memory file.
- `PromptBuilder.kt`'s system prompt documents the optional `"memory"`
  JSON field and instructs the brain to keep it under ~120 words and
  only update it when something changed.

## Batch G — in progress (paused before session limit)

Two new files are on disk and committed but **not yet wired in**:

- `core/A11yFastPath.kt` — cheap heuristic: after a successful TapMark
  the loop remembers the label; on subsequent ticks with the same
  label still visible AND small perceptual-hash delta, re-issues the
  tap without calling the brain. Capped at 3 consecutive fast-path
  ticks. Created but `DecisionLoop` does not call it yet.
- `overlay/DebugOverlayView.kt` — full-screen non-interactive View
  that draws current SoM mark boxes + highlights the last-tapped
  mark in red. Created but `OverlayService` does not add it to the
  WindowManager yet.

**To finish G in the next session:**

1. `core/AutopilotController.kt`: expose a `debugFrame: SharedFlow<DebugFrame>`
   (where `DebugFrame(marks, lastTappedMarkId)`) emitted from
   `buildSnapshot` / after each dispatch.
2. `overlay/OverlayService.kt`: when `Settings.showDebugOverlay` is on
   (new setting), add a second WindowManager view of type
   `TYPE_APPLICATION_OVERLAY` with flags
   `FLAG_NOT_FOCUSABLE | FLAG_NOT_TOUCHABLE | FLAG_LAYOUT_NO_LIMITS`
   sized to MATCH_PARENT, hosting `DebugOverlayView`. Collect the
   debug flow into `view.update(...)`. Remove on quit.
3. `core/DecisionLoop.kt`: before calling `brain.decide`, ask the
   `A11yFastPath` instance (held in the loop) for a fast-path action
   list; if non-null, dispatch those and skip the brain call. On
   normal brain decisions, call `fastPath.recordBrainDispatch(...)`.
   Add fastPath as a constructor parameter.
4. `core/AutopilotController.start()`: instantiate `A11yFastPath()` and
   pass to DecisionLoop. Reset it in `quit()`.
5. `data/Settings` + `SettingsRepository` + `SettingsActivity` + layout
   + strings: add `showDebugOverlay: Boolean = false` and
   `useFastPath: Boolean = true` toggles.

## Batch H — still not started

Extract `ScreenReader`, `ActionExecutor`, `Reasoner` interfaces. The
existing classes become default impls. Lets us later add Shizuku
executor / on-device Gemini-Nano reasoner without touching the loop.

## Architecture upgrades landed in F

- **Set-of-marks prompting.** Each tick, `CandidateExtractor` builds up
  to 80 `MarkBox` candidates from (clickable a11y nodes ∪ OCR line
  boxes), de-duplicated by IoU > 0.6, sorted by area DESC. The
  screenshot sent to the brain has translucent numbered rectangles
  drawn on top by `SetOfMarksOverlay`. The brain's system prompt now
  strongly prefers `tapMark`/`longPressMark`/`typeText` over raw
  pixel coordinates — VLMs are much better at picking IDs than coords.
- **`Action.TypeText`** routed via
  `AutopilotAccessibilityService.typeOnFocused()` →
  `AccessibilityNodeInfo.ACTION_SET_TEXT` on the focused editable
  node, with optional `IME_ENTER` submit.
- **Stuck-state circuit breaker.** `DecisionLoop` tracks a 3-tick
  rolling buffer of `dHash` values (`util/PerceptualHash`). If all
  three are within Hamming distance 5, sets `BrainContext.stuckHint`
  so the brain knows to try a recovery action; trips into
  `LoopPhase.ERROR` after 6 consecutive stuck ticks.
- **Cycle log.** `core/CycleLog` writes one JSONL line per tick to
  `filesDir/cycles/YYYY-MM-DD.log` (timestamp, hash, delta, mark count,
  thought, action labels, dispatch results, foreground pkg). Auto-prunes
  after 7 days. Toggle in Settings.

Note: `core/Action.kt` was moved up from Batch C to Batch B because the
brain depends on it (`BrainDecision.actions: List<Action>`).

## Already pushed

- `c80a455` — Gradle/module scaffold: root + `app/build.gradle.kts`,
  `settings.gradle.kts`, `gradle.properties`, wrapper, `.gitignore`,
  `proguard-rules.pro`.
- `fe1da06` — `PROGRESS.md` shared cross-session build log.
- (this commit) — Batch A.

## Key decisions to preserve (don't regress these)

- Package/namespace: `com.gameautopilot.app`. minSdk 26, target/compile 34.
  AGP 8.5.2, Kotlin 1.9.24, JDK 17, Gradle wrapper 8.7.
- **No** `org.json` Gradle dependency — Android ships it natively.
- **No** `buildFeatures.viewBinding` — use `findViewById`.
- `DecisionLoop.tick()` must treat `Action.Wait(ms)` as additive delay
  for the *next* tick, not a no-op. This is the most important behavioral
  fix — verify by inspection in Batch C.
- ML Kit text-recognition only for OCR (no OpenCV).
- Brain is OpenAI-compatible Chat Completions with vision (image_url with
  base64 jpeg). Default model `gpt-4o-mini`. NVIDIA NIM works by setting
  base URL to `https://integrate.api.nvidia.com/v1` + a vision-capable
  model. Anthropic & Gemini explicitly out of scope for v1.
- Screenshot encoding: longest edge ≤ 1024px, JPEG q=80, base64.
- API key stored in plain SharedPreferences (`autopilot_settings.xml`,
  excluded from backups). Documented in README. "Clear API key" button
  in Settings.
- Safety: per-game `targetPackage` foreground check before dispatch,
  configurable max actions/minute (default 30), always-visible
  Stop/Quit in overlay.
- Target repo: `viktorhedklin/androidapp`, branch
  `claude/android-game-autopilot-7mc6mx`. `main` is fast-forwarded from
  this branch on demand. No PR opens unless user asks.
- This is a **rebuild from a textual handoff description**, not a restore
  of the original 2-commit history (`1bfc063`, `e8fa68a`) — that bundle
  is unreachable from this environment.

## File layout (LLM-brain target)

```
app/src/main/
├── AndroidManifest.xml
├── res/{values,xml,layout,drawable,mipmap-anydpi-v26,menu}/...
└── java/com/gameautopilot/app/
    ├── App.kt
    ├── MainActivity.kt
    ├── ui/{GameListAdapter, AddGameActivity, AppPickerAdapter,
    │       SettingsActivity, PermissionsActivity, ProjectionRequestActivity}.kt
    ├── data/{Game, GameRepository, Settings, SettingsRepository}.kt
    ├── brain/{Brain, BrainContext, OpenAiCompatibleBrain, BrainFactory}.kt
    ├── core/{Action, ScreenSnapshot, ActionDispatcher, DecisionLoop,
    │         AutopilotController, ActionRing}.kt
    ├── accessibility/{AutopilotAccessibilityService, NodeTreeReader, GestureDispatcher}.kt
    ├── capture/{ScreenCaptureManager, ScreenshotEncoder}.kt
    ├── vision/OcrEngine.kt
    ├── overlay/{OverlayService, OverlayView}.kt
    └── util/{BitmapUtils, PermissionsUtil, Logger}.kt
```

Note: after Batch A the project **will not compile yet** — the manifest
references classes (`App`, `MainActivity`, `ui.*`, `accessibility.*`,
`overlay.OverlayService`) that don't exist until Batches B–D. This is
intentional pacing; the next batch is meaningful work and the manifest
is locked in.

---

## macOS port (`mac/`) — done, device-unverified (2026-07-09)

User asked whether the Android autopilot could become a Mac version,
then said "make it happen." **Not a port of the Kotlin code** — a new
native Swift app in `mac/`, same repo/branch, reusing the *brain
contract* (prompt shape, strict-JSON action schema, the 3 providers) and
*loop shape* (capture → perceive → think → act → wait, dHash stuck-state
breaker) but built entirely on macOS-native frameworks
(ScreenCaptureKit/AXUIElement/Vision/CGEvent instead of MediaProjection/
AccessibilityService).

**Locked decisions** (via AskUserQuestion): lives in `mac/` subfolder of
this repo (not a new repo), native Swift Package Manager (not a
hand-written `.xcodeproj`), v1 is a **menu bar utility**
(`MenuBarExtra`, no Dock icon) — pick a running app/window as target,
Start/Stop, no persisted multi-target library UI like Android's
`GameRepository`. Minimum target macOS 14 Sonoma (needed by
`SCScreenshotManager.captureImage`, the one-shot capture API).

**Critical constraint**: this sandbox has no macOS/Xcode/Swift-Apple-
frameworks toolchain — **nothing in `mac/` has compiled or run.**
Architecture was validated by a dedicated Plan-agent research pass before
writing any code (API choices, gotchas, concrete signatures for the
riskiest files), and every file was written carefully against that
research, but real verification is entirely on whoever builds this next
on an actual Mac. See `mac/README.md`'s "Known risk areas" section.

### Status table

| Step | Description | Status | Commit |
|------|------------------------------------------------|--------|---------|
| 1 | Skeleton: Package.swift, Info.plist, build.sh, minimal menu bar app | done | aee730f |
| 2 | Core primitives (MarkBox/ScreenSnapshot/ActionRing) + extended Action taxonomy | done | 9d59efe |
| 3 | Brain layer (Brain/PromptBuilder/BrainResponseParser/OpenAICompatibleBrain/GeminiBrain/BrainFactory) + Settings model | done | 63cdc06 |
| 4 | Perception + Capture (ScreenCapture, AccessibilityReader, OcrEngine, CandidateExtractor, SetOfMarksOverlay, ScreenshotEncoder) | done | 58df87d |
| 5 | ActionDispatcher (CGEvent) + Keychain + Permissions | done | 89993d3 |
| 6 | Orchestration (DecisionLoop actor, AutopilotController, TargetMemoryStore) + concurrency fixes | done | 8487658 |
| 7 | Menu bar UI (App.swift, MenuBarView, SettingsView, TargetPickerView, OnboardingView) | done | b1ce2ae |
| 8 | mac/README.md + this PROGRESS.md section | done | (this commit) |

**Next**: build on a real Mac, fix whatever doesn't compile (the README
flags the most likely trouble spots), test against a real target app.
Nothing further is planned server-side until that feedback loop happens.

### Key decisions to preserve

- Package/bundle id: `com.gameautopilot.mac`, chosen once and meant to
  stay fixed — TCC ties Accessibility/Screen Recording grants to
  bundle id + code signature, so changing it later forces re-granting.
- **Ad-hoc codesigning (`codesign --sign -`, `build.sh`'s default)
  changes identity every rebuild**, forcing a permission re-grant after
  every build. `build.sh --sign "cert name"` with a one-time
  self-signed persistent certificate (documented in `mac/README.md`)
  avoids this — important enough to repeat here since it's the single
  most annoying thing to discover the hard way during dev.
- No build/compile verification was possible in this sandbox, so
  correctness leaned on getting documented API shapes right the first
  time rather than iterating on compiler feedback. Two real concurrency
  bugs were caught and fixed during the build itself (not by a
  compiler): `ActionDispatcher` originally captured mutable state via
  closures across actor boundaries (fixed by threading `bounds` as a
  per-call parameter and `targetPID` as a fixed `let`), and
  `TargetMemoryStore.cache` was mutated from both `DecisionLoop`'s actor
  and the UI with no lock (fixed with `NSLock`). Worth extra scrutiny on
  any future concurrency-touching change here, precisely because it
  can't be compiler-checked from this environment.
- Vision's OCR `boundingBox` is bottom-left-origin/normalized — flipped
  to top-left-origin pixels inside `OcrEngine.swift` so every other file
  only ever deals with one coordinate convention (matching AX/CGEvent/
  screenshot pixel space). `SetOfMarksOverlay.swift` deliberately does
  **not** apply a CTM flip to its CGContext (a manual flip would have
  turned the base screenshot upside down, since `CGContext.draw(_:in:)`
  already orients an image correctly in a context's native bottom-left/
  Y-up space) — each mark's rect converts its own Y instead.
  `NSGraphicsContext(cgContext:flipped:false)` is used for text drawing
  to match.
- Action taxonomy diverges from Android on purpose: `back` (hardware
  button) → `keyPress(keys:)`; added `doubleClick`/`rightClick`/`scroll`
  since a held-button drag is a selection gesture on Mac, not a scroll.
- API key lives in Keychain from day one (`Util/Keychain.swift`), never
  in `Settings`/`UserDefaults` — a deliberate improvement over Android's
  documented plaintext-SharedPreferences tradeoff, cheap enough to just
  do properly here.
- `AutopilotController` is deliberately **not** class-wide `@MainActor`
  — only state-mutating methods are, so `buildSnapshot()`'s OCR/AX/
  image-encoding work doesn't run on the main actor and jank the status
  item.
- Zero third-party SPM dependencies — everything used is a system
  framework.

---

## Intelligence upgrade (`mac/`) — done, device-unverified (2026-07-10)

User asked for three things after the Mac app was building and running
on real hardware: (1) pre-game research — type a name, AI confirms it
understands the target before Start is ever pressed; (2) explicit goal
specification, since "finish the full gameplay" and "spin slots to gain
level" are behaviorally different, not just different text; (3) ad/
interruption recovery — "get back to the game" if a click accidentally
opens the App Store. User also asked for a specific process: **3 parallel
agent reviews (2x opus, 1x haiku) + 1 QA pass (haiku), then user approval
via ExitPlanMode, before any code** — all four ran against a design draft
in the Claude-Code plan file before implementation started. That review
process is what caught the real problems below; the first draft would
have shipped a worse design.

### What review caught (would have been wrong without it)

- **Removing the frontmost-skip entirely (the naive fix) would have made
  the bot fight the user for focus and burn paid API calls every tick
  whenever they deliberately alt-tabbed away** — worse than the bug it
  fixed. Fixed with bounded recovery: try for `interruptionRecoveryTicks`
  (5) consecutive not-frontmost ticks, then back off to a 10x-interval
  brain-free poll until frontmost naturally matches again.
- **`keyPress` needed blocking alongside clicks when the target isn't
  frontmost** — a CGEvent keyboard event goes to whichever app currently
  has keyboard focus (the interrupter), not the blind target. A
  "recovery" `keyPress(["cmd","w"])` would land on the wrong app. Only
  `switchToTarget`/`wait`/`noop` pass through during a window-path
  interruption (`Action.requiresTargetFrontmost`).
- **The capture-blindness claim was path-dependent, not absolute**: true
  for window-specific `SCContentFilter(desktopIndependentWindow:)`
  capture (the screenshot is a stale/frozen buffer during a cross-app
  redirect, genuinely invisible to the brain), but false for the
  fullscreen `SCContentFilter(display:...)` fallback, which actually
  shows the interrupter. Action-class filtering only applies on the
  window path; display-path targets keep full freedom to visually
  recover.
- **`switchToTarget` needed to re-resolve by bundle identifier, not a
  cached PID** — if the interruption killed/relaunched the target, a
  cached `pid_t` goes stale and `NSRunningApplication(pid:)` silently
  returns nil.
- **The loop had no way to stop itself** — "finish the full gameplay"
  wasn't actually implementable before this: the loop would finish the
  game and then keep poking a completed screen forever. Added
  `BrainDecision.goalComplete` (additive, same pattern as
  `memoryUpdate`) + `TargetProfile.goalMode` (`.playUntilComplete` /
  `.keepRunning`) + `LoopPhase.completed`, intercepted in
  `AutopilotController.updatePhase` and turned into a terminal
  `.idle(note: "Goal complete!")` rather than displayed as an ongoing
  running phase.
- **The original research design defaulted to requiring a second
  (Gemini) API key for every user on OpenAI/NVIDIA** — flipped to:
  research runs through whichever provider is already configured by
  default (zero new keys, works universally, fine for any reasonably
  known target), with Gemini `google_search` grounding as an **optional**
  upgrade (separate Keychain slot `"researchApiKey"`) for live results.
  Gemini's search tool and `responseMimeType: json` don't reliably
  coexist, so `GameResearcher` asks for JSON in the prompt text and
  parses leniently instead of using strict response mode.
- **The original setup-wizard design was a multi-round chat** ("ask
  until the model has no more questions") — UX review called this
  over-built for a menu-bar utility and a scope-creep risk toward a
  "chat app" the v1 decision deliberately avoided. Simplified to one
  research pass → one consolidated (0-3) question list → Save, all of
  it optional and skippable. **Known targets skip setup entirely** —
  picking a target with an existing `TargetProfile` goes straight to
  Start-ready, no re-interrogation (a real gap fixed along the way: the
  prompt wasn't persisted *at all* before this batch).
- **`TargetProfileStore` does NOT need `TargetMemoryStore`'s `NSLock`
  pattern** — confirmed by both the risk review and the QA pass:
  profiles are only ever read (`selectTarget`) and written
  (`TargetSetupView`) from `@MainActor`, unlike memory, which is
  genuinely written from `DecisionLoop`'s actor via `onMemoryUpdate`.
  Copying the lock pattern here would have been unnecessary complexity
  implying a requirement that doesn't exist.

### New/changed files

- `Research/GameResearcher.swift` (new) — one-shot research call, not
  routed through the `Brain` protocol (structurally different from the
  per-tick gameplay contract: no screenshot, no strict JSON mode).
- `Core/TargetProfile.swift` (new) — `GoalMode` enum + `TargetProfile`
  (no persisted Q&A transcript, just what feeds the prompt) +
  `TargetProfileStore`.
- `UI/TargetSetupView.swift` (new) — name/info/goal/goal-mode, optional
  Research, optional consolidated questions, Save. Real `Window` scene
  (`App.swift`), not `.sheet()`.
- `Brain/Brain.swift` — `BrainContext.targetIsFrontmost` +
  `BrainContext.goalMode`, `BrainDecision.goalComplete`. `BrainError`
  gained `LocalizedError` conformance (a real bug: `CustomStringConvertible`
  alone doesn't make `.localizedDescription` use `message`).
- `Brain/BrainResponseParser.swift` — parses `goalComplete`.
- `Action/Action.swift` — `switchToTarget` case +
  `requiresTargetFrontmost` classification.
- `Action/ActionDispatcher.swift` — `targetPID: pid_t?` replaced by
  `targetBundleIdentifier: String?` throughout (fixes the staleness risk
  for `typeText`'s existing activate-fallback too, not just the new
  action); `switchToTarget` re-resolves via `NSWorkspace` each call.
- `Core/DecisionLoop.swift` — bounded recovery/backoff, path-aware
  action filtering, suppressed stuck-hash recording during window-path
  interruption (a frozen buffer would otherwise trip the stuck breaker
  before recovery gets a fair shot), `LoopPhase.completed` handling.
- `Brain/PromptBuilder.swift` — `switchToTarget`/`goalComplete` in the
  JSON schema, goal-mode-aware completion guidance, path-aware
  interruption-recovery section.
- `Core/AutopilotController.swift` — `selectTarget(_:profile:)` replaces
  `selectTarget(_:prompt:)`; wires `TargetProfileStore`,
  `pendingSetupTarget` hand-off slot, `updatePhase` intercepts
  `.completed`.
- `UI/MenuBarView.swift` — shows the saved goal + "Edit setup…" for a
  known target; fixed a real display bug found while wiring this in
  (`AutopilotState.idle(note:)`'s note was never actually shown —
  `statusText`'s `.idle` case ignored it and always printed "Idle").
- `UI/SettingsView.swift` — optional research-key field (separate
  Keychain slot, own "Clear" button).
- `UI/TargetPickerView.swift` — Select routes to
  `controller.selectTarget` directly for a known target, or to
  `TargetSetupView` via `pendingSetupTarget` for a new one.

### Known limitation not fixed in this batch (scope discipline, not an oversight)

`AutopilotController.buildSnapshot`'s AX reads use a `pid` captured once
at `start()` time (closed over in the `takeSnapshot` closure), same as
before this batch — if the target relaunches with a new PID mid-run,
accessibility-tree reads go stale the same way `switchToTarget`'s cached
PID used to. Not touched here since it wasn't part of what was reviewed/
approved; likely graceful-degrades to empty a11y marks for a tick (OCR
still works) rather than crashing, but worth fixing in a follow-up if it
turns out to matter in practice.

---

## Fix: Settings/target windows losing focus on real hardware (2026-07-10)

User reported on real hardware, after the `.sheet()`→`Window` fix from
the previous round: "still cant press the menu, it minimize when trying
to add the api." Different symptom from the original bug (that one was
the whole popover auto-dismissing on outside clicks; this is the
secondary `Window` itself never becoming key).

Root cause: this app is `LSUIElement=true` (accessory app, no Dock icon,
no icon to click to reactivate). Accessory apps on macOS don't reliably
get frontmost/key-window status for a `Window` scene opened via
`openWindow(id:)` from a `MenuBarExtra` — the window can appear behind
or simply never accept keyboard/click focus, which reads as it
"minimizing" the moment you try to type.

Fix: added `.onAppear { NSApp.activate(ignoringOtherApps: true) }` to
all three secondary `Window`-scene views —
`UI/SettingsView.swift`, `UI/TargetPickerView.swift`,
`UI/TargetSetupView.swift` (folded into its existing `.onAppear` next to
`loadPending()`). Forces the app to the front and grabs key status
explicitly instead of relying on the default accessory-app activation
behavior. `NSApp`/`NSApplication` resolve without an explicit
`import AppKit`, consistent with the existing `NSApplication.shared`
call already in `UI/MenuBarView.swift` — SwiftUI re-exports AppKit on
macOS.

Still device-unverified by me (no macOS toolchain in this sandbox) —
needs a real-hardware retest: open Settings from the menu bar, click
into the API key field, confirm the window stays focused and typing
works, then repeat for "Pick target..." and "Edit setup...".

### Follow-up: `NSApp.activate()` alone wasn't the fix (2026-07-10)

User retested and reported the same symptom persisting. Real root cause
was different from what the `NSApp.activate()` change addressed: the
`MenuBarExtra(.window)` popover only auto-dismisses on an *outside*
click — clicking "Settings..." (a button inside the popover) opens the
Settings `Window` but does **not** close the popover itself. So both the
popover and the new window were open simultaneously, competing for key
status; the moment the user clicked into the Settings window to type,
the still-open popover (or the click landing on/near it) won the
fight, and the new window appeared to vanish/"minimize."

Fix: `UI/MenuBarView.swift` now holds `@Environment(\.dismiss)` and
routes every window-opening button (`Settings...`, `Change target...`,
`Pick target...`, `Edit setup...`) through a new `openTarget(_ id:)`
helper that calls `openWindow(id:)` immediately followed by `dismiss()`
— closing the MenuBarExtra popover explicitly the same way a real
outside click would, so only the new window is left on screen instead
of two top-level surfaces contending for focus. The `NSApp.activate()`
calls from the previous fix stay in place as a secondary safeguard once
only one window remains.

Still device-unverified — same retest steps as above, this time also
watching whether the popover itself visibly closes the instant the
button is clicked.
