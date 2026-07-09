import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Dispatches Actions via CGEvent (clicks/drags/scroll/keys), posted at
/// .cghidEventTap -- the most broadly compatible tap location, including
/// with fullscreen/game-mode apps (.cgSessionEventTap doesn't reach those
/// as reliably). Text input prefers AXUIElement, falling back to CGEvent
/// unicode-string synthesis. Mirrors core/ActionDispatcher.kt +
/// accessibility/GestureDispatcher.kt combined.
final class ActionDispatcher {
    private let screenBounds: () -> CGRect
    private let targetPID: () -> pid_t?

    init(screenBounds: @escaping () -> CGRect, targetPID: @escaping () -> pid_t?) {
        self.screenBounds = screenBounds
        self.targetPID = targetPID
    }

    @discardableResult
    func dispatch(_ action: Action, marks: [MarkBox]) async -> Bool {
        switch action {
        case .tap(let x, let y):
            return click(x: x, y: y, button: .left, clickCount: 1)
        case .tapMark(let id):
            guard let m = mark(id, marks) else { return false }
            return click(x: m.cx, y: m.cy, button: .left, clickCount: 1)
        case .doubleClick(let x, let y):
            return click(x: x, y: y, button: .left, clickCount: 2)
        case .doubleClickMark(let id):
            guard let m = mark(id, marks) else { return false }
            return click(x: m.cx, y: m.cy, button: .left, clickCount: 2)
        case .rightClick(let x, let y):
            return click(x: x, y: y, button: .right, clickCount: 1)
        case .rightClickMark(let id):
            guard let m = mark(id, marks) else { return false }
            return click(x: m.cx, y: m.cy, button: .right, clickCount: 1)
        case .longPress(let x, let y, let durationMs):
            return await hold(x: x, y: y, durationMs: durationMs)
        case .longPressMark(let id, let durationMs):
            guard let m = mark(id, marks) else { return false }
            return await hold(x: m.cx, y: m.cy, durationMs: durationMs)
        case .swipe(let x1, let y1, let x2, let y2, let durationMs):
            return await drag(x1: x1, y1: y1, x2: x2, y2: y2, durationMs: durationMs)
        case .scroll(let x, let y, let deltaX, let deltaY):
            return scroll(x: x, y: y, deltaX: deltaX, deltaY: deltaY)
        case .typeText(let text, let submit):
            return await typeText(text, submit: submit)
        case .keyPress(let keys):
            return keyPress(keys)
        case .wait(let ms):
            try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000)
            return true
        case .noop:
            return true
        }
    }

    // MARK: - Helpers

    private func mark(_ id: Int, _ marks: [MarkBox]) -> MarkBox? {
        guard let m = marks.first(where: { $0.id == id }) else {
            Logger.w("Mark id=\(id) not in current marks (size=\(marks.count))")
            return nil
        }
        return m
    }

    private func inBounds(_ x: Int, _ y: Int) -> Bool {
        let b = screenBounds()
        return CGFloat(x) >= b.minX && CGFloat(x) < b.maxX && CGFloat(y) >= b.minY && CGFloat(y) < b.maxY
    }

    // MARK: - Mouse

    private func click(x: Int, y: Int, button: CGMouseButton, clickCount: Int64) -> Bool {
        guard inBounds(x, y) else {
            Logger.w("Skipping out-of-bounds click (\(x),\(y))")
            return false
        }
        let point = CGPoint(x: x, y: y)
        let (downType, upType): (CGEventType, CGEventType) = button == .left
            ? (.leftMouseDown, .leftMouseUp)
            : (.rightMouseDown, .rightMouseUp)

        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: button)
        else { return false }

        // Click = down+up pair, not one call. Double-click needs
        // mouseEventClickState=2 on both events.
        down.setIntegerValueField(.mouseEventClickState, value: clickCount)
        up.setIntegerValueField(.mouseEventClickState, value: clickCount)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func hold(x: Int, y: Int, durationMs: Int) async -> Bool {
        guard inBounds(x, y) else {
            Logger.w("Skipping out-of-bounds long-press (\(x),\(y))")
            return false
        }
        let point = CGPoint(x: x, y: y)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return false }
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: UInt64(max(0, durationMs)) * 1_000_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func drag(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int) async -> Bool {
        guard inBounds(x1, y1), inBounds(x2, y2) else {
            Logger.w("Skipping out-of-bounds drag")
            return false
        }
        let start = CGPoint(x: x1, y: y1)
        let end = CGPoint(x: x2, y: y2)

        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        else { return false }
        down.post(tap: .cghidEventTap)

        // A teleporting down->up will not register as a drag in most apps
        // (unlike Android's declarative, OS-interpolated GestureDescription)
        // -- interpolate intermediate .leftMouseDragged events by hand.
        let steps = max(4, min(30, durationMs / 16))
        let stepDelayNs = UInt64(max(1, durationMs) * 1_000_000 / steps)
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let x = Double(start.x) + (Double(end.x) - Double(start.x)) * t
            let y = Double(start.y) + (Double(end.y) - Double(start.y)) * t
            if let move = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                   mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
                move.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(nanoseconds: stepDelayNs)
        }

        up.post(tap: .cghidEventTap)
        return true
    }

    private func scroll(x: Int, y: Int, deltaX: Int, deltaY: Int) -> Bool {
        guard inBounds(x, y) else {
            Logger.w("Skipping out-of-bounds scroll (\(x),\(y))")
            return false
        }
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else { return false }
        scrollEvent.location = CGPoint(x: x, y: y)
        scrollEvent.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Keyboard

    private func typeText(_ text: String, submit: Bool) async -> Bool {
        var ok = false
        if let element = AccessibilityReader.focusedEditableElement() {
            ok = AccessibilityReader.setValue(element, text: text)
        }
        if !ok {
            activateTargetIfNeeded()
            ok = postUnicodeString(text)
        }
        if ok && submit {
            pressReturn()
        }
        return ok
    }

    private func activateTargetIfNeeded() {
        guard let pid = targetPID(), let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }

    /// Layout-independent text synthesis -- avoids per-character keycode
    /// lookup entirely. Used when no focused AX-settable text field is
    /// found (common for game-rendered text fields with no settable AX
    /// value).
    private func postUnicodeString(_ text: String) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else { return false }
        let utf16 = Array(text.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func pressReturn() {
        guard let code = KeyCode.code(for: "return") else { return }
        postKey(code, flags: [])
    }

    private func keyPress(_ keys: [String]) -> Bool {
        let modifierNames = keys.filter { KeyCode.modifierNames.contains($0.lowercased()) }
        let realKeys = keys.filter { !KeyCode.modifierNames.contains($0.lowercased()) }
        guard let keyName = realKeys.first, let code = KeyCode.code(for: keyName) else {
            Logger.w("keyPress: no resolvable key in \(keys)")
            return false
        }
        var flags: CGEventFlags = []
        for name in modifierNames {
            if let f = KeyCode.flag(for: name) { flags.insert(f) }
        }
        postKey(code, flags: flags)
        return true
    }

    private func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
