# Game Autopilot -- macOS

A menu-bar utility that watches a chosen app/window via a vision LLM
(OpenAI, NVIDIA NIM, or Google Gemini), reasons about what it sees, and
dispatches synthetic clicks/drags/scrolls/keystrokes to operate it on
your behalf. Same brain contract as the Android app in the repo root --
same set-of-marks prompting, same strict-JSON action schema, same
persistent per-target memory -- but a completely different, native
implementation: macOS has no MediaProjection/AccessibilityService/APK, so
this is built on ScreenCaptureKit, AXUIElement, Vision, and CGEvent.

**This has not been built or run on a real Mac.** It was written from a
Linux sandbox with no Xcode/Swift-Apple-frameworks toolchain available,
so nothing here has compiled successfully yet -- see "Known risk areas"
below before relying on it.

## Build

Requires macOS 14 Sonoma+ and Xcode 15+ (for the Swift 5.9 toolchain).

```bash
cd mac
./build.sh
open GameAutopilot.app
```

`build.sh` runs `swift build -c release`, assembles the output into a
proper `.app` bundle, and codesigns it. **Do this once, first:** ad-hoc
signing (the default) derives its identity from the binary's content
hash, so it changes on *every rebuild* -- macOS will make you re-grant
Accessibility and Screen Recording after every single build. Avoid that
during development:

1. Open **Keychain Access** -> menu bar **Keychain Access > Certificate
   Assistant > Create a Certificate...**
2. Name: `GameAutopilotMac Dev`. Identity Type: **Self Signed Root**.
   Certificate Type: **Code Signing**.
3. Build with: `./build.sh --sign "GameAutopilotMac Dev"`

That identity is stable across rebuilds, so permissions only need
granting once.

Prefer Xcode's GUI/debugger? `File > Open...` the `mac/` folder directly
-- Xcode treats an SPM package as a native project, no `.xcodeproj`
needed. Note: a run from Xcode has a different code identity/path than
`build.sh`'s `.app`, so you may need to grant permissions separately for
each.

## Permissions

Two System Settings toggles, both requested from the menu bar dropdown
when either is missing:

1. **Screen Recording** -- required to capture the target window/display.
   No usage-description string exists for this in Info.plist (unlike
   camera/mic); it's purely TCC-driven. macOS 15+ re-prompts periodically
   (roughly monthly) -- that's expected, not a bug.
2. **Accessibility** -- required to read the target's UI element tree and
   to post synthetic clicks/keystrokes system-wide.

Both link directly to their System Settings pane from the app.

## Using it

1. Launch the app -- a controller icon appears in the menu bar (no Dock
   icon, it's `LSUIElement`).
2. Click it -> grant the two permissions if prompted.
3. **Pick target...** -> choose a running app's window from the list,
   optionally describe what it should do.
4. **Settings...** -> pick a provider (OpenAI / NVIDIA NIM / Google
   Gemini), paste an API key (stored in Keychain, never in plaintext).
5. **Start.** Status dot/text shows idle / thinking / acting / error.
   **Stop** pauses the loop; **Release target** clears it entirely.

Per-target memory (the brain's own notes on goal/progress) persists
across runs and app restarts, keyed by bundle identifier. **Reset
memory** in the target section wipes it for the current target.

## Known risk areas (read before relying on this)

This was written against Apple's documented API shapes and cross-checked
by a dedicated design/validation pass, but **zero compile-time or
runtime verification was possible** from the sandbox that wrote it. In
rough order of "most likely to bite first":

- **Fullscreen/native game capture.** Cross-Space window capture (a game
  running in its own fullscreen Space) has a documented history of
  returning blank frames on some macOS versions. There's a display-based
  fallback in `Capture/ScreenCapture.swift`, but which path actually
  fires for a real fullscreen game needs testing on real hardware.
- **Sparse accessibility trees.** Native-rendered games (raw Metal/SDL/
  Unity/Unreal) commonly expose a single opaque AX root with no useful
  children. Expect OCR to carry most of the signal for anything that
  isn't a fairly standard Mac app (browsers, native utilities, Electron
  apps with decent AX support).
- **SwiftUI `.sheet()` inside `MenuBarExtra(.window)`.** Presenting
  TargetPickerView/SettingsView as sheets from a menu-bar-hosted window
  should work on macOS 13+, but this exact combination wasn't something
  I could visually confirm.
- **CGEvent drag/scroll registering correctly** in third-party apps --
  the interpolated-drag and scroll-wheel-event code follows documented
  patterns but needs a real app to confirm timing/step-count feel right.
- **Anti-cheat/DRM.** Some games detect synthetic CGEvents via event
  source state ID. Out of scope to defeat -- this is a personal-use tool
  for casual/non-DRM'd games, not built to evade anti-cheat.

If something doesn't build: the most likely culprits are exact API
signatures for `SCScreenshotManager.captureImage`, `SCContentFilter`'s
`contentRect`/`pointPixelScale` properties, or
`CGEvent(scrollWheelEvent2Source:...)`'s parameter labels -- these were
written from documented API shape, not verified against a live SDK.

## What leaves your device

Same as the Android app: every tick, the screenshot, OCR'd text, a
flattened accessibility-element list, and the persistent per-target
memory notes are sent to whichever provider you've configured. If the
target app shows personal info on screen, that leaves your device on
every tick while running.

## Architecture

```
mac/Sources/GameAutopilotMac/
├── App.swift                      MenuBarExtra entry point
├── Capture/                       ScreenCaptureKit one-shot capture + JPEG encode
├── Perception/                    AXUIElement tree read, Vision OCR, mark merging/overlay
├── Brain/                         Provider-agnostic prompt/schema + OpenAI-compatible + Gemini
├── Action/                        Action enum + CGEvent dispatch + rate limiter
├── Core/                          DecisionLoop (actor), AutopilotController, Settings, memory store
├── UI/                            MenuBarView, SettingsView, TargetPickerView, OnboardingView
└── Util/                          Logger, Keychain, KeyCode table, PerceptualHash, Permissions
```

No third-party dependencies -- Foundation/AppKit/SwiftUI/ScreenCaptureKit/
Vision/ApplicationServices/Security are all system frameworks.

See `PROGRESS.md` at the repo root for the cross-session build log and
design rationale (search for "macOS port").
