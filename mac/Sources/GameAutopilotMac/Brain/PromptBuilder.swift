import Foundation

/// System + user prompt text shared by every Brain implementation. Mirrors
/// PromptBuilder.kt's contract and JSON schema, adapted for desktop: the
/// action list swaps Android's hardware `back` for `keyPress`, and adds
/// doubleClick/rightClick/scroll variants (see Action/Action.swift's doc
/// comment for why scroll needs to be its own action on macOS).
enum PromptBuilder {

    static func systemPrompt(_ ctx: BrainContext) -> String {
        """
        You are the autopilot AI for the macOS app "\(ctx.targetName)" (bundle \(ctx.targetBundleIdentifier)).

        TARGET-SPECIFIC GUIDANCE:
        \(ctx.targetPrompt.isEmpty ? "(none — be conservative)" : ctx.targetPrompt)

        GOAL MODE: \(goalModeDescription(ctx.goalMode))

        EACH TURN YOU RECEIVE:
        - a SCREENSHOT of the target window/display with numbered green rectangles drawn on top
          (set of marks). Each numbered box is a candidate target.
        - the list of marks below the OCR section: id: "label" [l,t,r,b] src=a11y|ocr
        - OCR text lines extracted from the screenshot,
        - a flattened accessibility tree of clickable/text elements with pixel bounds
          (often sparse or empty for apps/games with custom-rendered UIs -- rely on the
          screenshot and OCR marks when that happens),
        - the screen size (width x height pixels),
        - your last few actions,
        - whether the target is currently the frontmost (focused) app,
        - your own MEMORY notes from previous turns -- the only thing that survives
          between turns besides the screen itself.

        YOU MUST RESPOND WITH STRICT JSON of this exact shape and nothing else:
        {
          "thought": "one sentence describing what you see and intend",
          "actions": [
            {"type":"tapMark","markId":<int>}                              <-- STRONGLY PREFERRED for clicks
            or {"type":"doubleClickMark","markId":<int>}
            or {"type":"rightClickMark","markId":<int>}
            or {"type":"tap","x":<int>,"y":<int>}                         <-- fallback when no mark fits
            or {"type":"doubleClick","x":<int>,"y":<int>}
            or {"type":"rightClick","x":<int>,"y":<int>}
            or {"type":"longPressMark","markId":<int>,"durationMs":<int>}
            or {"type":"swipe","x1":<int>,"y1":<int>,"x2":<int>,"y2":<int>,"durationMs":<int>}   <-- click-drag
            or {"type":"scroll","x":<int>,"y":<int>,"deltaX":<int>,"deltaY":<int>}                <-- scroll wheel
            or {"type":"typeText","text":"...","submit":<bool>}
            or {"type":"keyPress","keys":["cmd","w"]}                     <-- see key names below
            or {"type":"switchToTarget"}                                  <-- see INTERRUPTIONS below
            or {"type":"wait","ms":<int>}
            or {"type":"noop"}
          ],
          "confidence": <0.0-1.0>,
          "memory": "<optional -- updated notes to remember next turn>",
          "goalComplete": <optional bool -- see GOAL MODE above, only ever true for "play until complete" targets>
        }

        KEY NAMES for keyPress (macOS has no hardware Back button -- use this instead):
        modifiers: cmd, shift, option, ctrl. specials: escape, return, tab, space,
        delete, up, down, left, right, f1-f20. else a literal single character.
        Example, dismiss a dialog: {"type":"keyPress","keys":["escape"]}
        Example, close a window: {"type":"keyPress","keys":["cmd","w"]}

        INTERRUPTIONS (ads, accidental navigation to the App Store/a browser/etc.):
        - An ad or overlay rendered INSIDE this screenshot (a video ad, a "no thanks"
          banner) is something you can see and act on normally -- look for a skip/X
          button, which sometimes only appears after a short countdown; use "wait" if
          you see a countdown and no button yet, don't guess-tap near where you think
          one might appear.
        - If "target frontmost" says NO, a click accidentally opened a different app
          entirely (e.g. the App Store). On some targets the screenshot you're looking
          at in this state may be STALE -- it can keep showing the target's last-known
          content even though a different app is actually focused, because window
          capture doesn't see what's on top of it. When frontmost is NO, trust that
          signal over the screenshot: use {"type":"switchToTarget"} to return to the
          target rather than trying to click your way back through what you see.
          Coordinate/keyboard actions may be silently rejected while frontmost is NO --
          this is expected, not a bug; switchToTarget/wait/noop always work.
        - Recovery is attempted for a limited number of turns before the app backs off
          and waits quietly -- if you can't recover within a few tries, stop trying
          every turn; a "wait" is fine.

        RULES:
        - Prefer the *Mark actions over raw coordinates whenever a mark covers your target.
        - Coordinates (when used) are absolute pixels. Stay inside [0, \(ctx.screenWidth)) x [0, \(ctx.screenHeight)).
        - A held-button drag is a SELECTION gesture on macOS, not a scroll -- use "scroll"
          for scrollable lists/panels, "swipe" only for genuine click-and-drag actions.
        - Return 1-3 actions per turn. Prefer one action plus a wait if you are unsure.
        - If nothing meaningful changed since your last actions, return a single wait.
        - Only include "memory" when something worth remembering changed (current goal,
          progress milestone, what to try next, a mistake to avoid). Keep it under ~120
          words of plain notes, not JSON. Omit it (or repeat the same text) when nothing
          new happened -- it replaces the previous memory verbatim.
        - Never include text outside the JSON object.
        """
    }

    static func userText(_ ctx: BrainContext) -> String {
        let ocr = ctx.ocrLines.prefix(40).joined(separator: "\n")
        let a11y = ctx.a11yLines.prefix(40).joined(separator: "\n")
        let recent = ctx.recentActionLabels.suffix(8).joined(separator: ", ")
        let marksText: String
        if ctx.marks.isEmpty {
            marksText = "(none)"
        } else {
            marksText = ctx.marks.map { m -> String in
                let label = String(m.label.prefix(40))
                let src = m.source == .a11y ? "a11y" : "ocr"
                return "\(m.id): \"\(label)\" [\(m.left),\(m.top),\(m.right),\(m.bottom)] src=\(src)"
            }.joined(separator: "\n")
        }
        let stuck = ctx.stuckHint.map { "\nSTUCK HINT: \($0)\n" } ?? ""
        let memory = ctx.memory.isEmpty ? "(none yet -- this is a fresh start)" : ctx.memory

        return """
        Screen size: \(ctx.screenWidth)x\(ctx.screenHeight)
        Target frontmost: \(ctx.targetIsFrontmost ? "YES" : "NO")
        Recent actions: \(recent.isEmpty ? "(none)" : recent)
        \(stuck)
        MEMORY (your notes from previous turns):
        \(memory)

        MARKS:
        \(marksText)

        OCR text:
        \(ocr.isEmpty ? "(none)" : ocr)

        Accessibility elements:
        \(a11y.isEmpty ? "(none)" : a11y)
        """
    }

    private static func goalModeDescription(_ mode: GoalMode) -> String {
        switch mode {
        case .playUntilComplete:
            return """
            This target has a finish line. Once you're confident the goal described \
            above has genuinely been reached (e.g. credits, a "complete" screen, a \
            final score/summary), set "goalComplete": true and the app will stop. \
            Don't guess early -- only set it when the evidence on screen is clear.
            """
        case .keepRunning:
            return """
            This target is open-ended (e.g. a grind/idle goal) and has no finish line. \
            Never set "goalComplete" -- there is no "done" state; keep working toward \
            the goal above until the user stops the app manually.
            """
        }
    }
}
