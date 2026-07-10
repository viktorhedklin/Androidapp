import Foundation

/// The brain's action vocabulary. Extends Android's Action.kt for desktop:
/// `back` (a hardware button on Android) has no macOS equivalent and is
/// replaced by `keyPress` (e.g. ["escape"] to dismiss, ["cmd","w"] to
/// close a window); `doubleClick`/`rightClick` and `scroll` are new since
/// desktop apps lean on them in ways touch UIs don't -- a held-button drag
/// is usually a *selection* gesture on Mac, not a scroll, so scrollable
/// lists need genuine scroll-wheel events (see ActionDispatcher.swift).
enum Action: Equatable {
    case tap(x: Int, y: Int)
    case tapMark(id: Int)
    case doubleClick(x: Int, y: Int)
    case doubleClickMark(id: Int)
    case rightClick(x: Int, y: Int)
    case rightClickMark(id: Int)
    case longPress(x: Int, y: Int, durationMs: Int)
    case longPressMark(id: Int, durationMs: Int)
    case swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int)
    case scroll(x: Int, y: Int, deltaX: Int, deltaY: Int)
    case typeText(text: String, submit: Bool)
    case keyPress(keys: [String])
    /// Coordinate-free recovery action: re-activates the target app by
    /// bundle identifier. The only way to "go back" when a different app
    /// is frontmost -- clicks/keystrokes would land on whatever app
    /// currently owns the screen/keyboard focus, not the target.
    case switchToTarget
    case wait(ms: Int)
    case noop

    /// False for the handful of actions that are safe to dispatch even
    /// when the target isn't frontmost (they don't depend on the target
    /// owning screen/keyboard focus). Used by DecisionLoop to filter the
    /// action set during a window-path interruption, where the brain is
    /// reasoning from a stale/frozen screenshot and has no reliable way
    /// to know what a click or keystroke would actually land on.
    var requiresTargetFrontmost: Bool {
        switch self {
        case .switchToTarget, .wait, .noop: return false
        default: return true
        }
    }

    var shortLabel: String {
        switch self {
        case .tap(let x, let y): return "tap(\(x),\(y))"
        case .tapMark(let id): return "tapMark(\(id))"
        case .doubleClick(let x, let y): return "doubleClick(\(x),\(y))"
        case .doubleClickMark(let id): return "doubleClickMark(\(id))"
        case .rightClick(let x, let y): return "rightClick(\(x),\(y))"
        case .rightClickMark(let id): return "rightClickMark(\(id))"
        case .longPress(let x, let y, let ms): return "longPress(\(x),\(y),\(ms)ms)"
        case .longPressMark(let id, let ms): return "longPressMark(\(id),\(ms)ms)"
        case .swipe(let x1, let y1, let x2, let y2, _): return "swipe(\(x1),\(y1)\u{2192}\(x2),\(y2))"
        case .scroll(let x, let y, let dx, let dy): return "scroll(\(x),\(y),dx=\(dx),dy=\(dy))"
        case .typeText(let text, let submit): return "type(\(text.prefix(20))\(submit ? "+return" : ""))"
        case .keyPress(let keys): return "key(\(keys.joined(separator: "+")))"
        case .switchToTarget: return "switchToTarget"
        case .wait(let ms): return "wait(\(ms)ms)"
        case .noop: return "noop"
        }
    }

    /// Parses one action object from the brain's strict-JSON `actions[]`
    /// array. Mirrors Action.kt's fromJson: returns nil on anything
    /// malformed rather than throwing -- callers skip bad entries so one
    /// off-shape action doesn't discard an otherwise-good cycle.
    static func from(json obj: [String: Any]) -> Action? {
        let type = (obj["type"] as? String ?? "").lowercased()

        func int(_ key: String, _ fallback: Int = -1) -> Int {
            if let i = obj[key] as? Int { return i }
            if let d = obj[key] as? Double { return Int(d) }
            if let n = obj[key] as? NSNumber { return n.intValue }
            return fallback
        }
        func str(_ key: String) -> String { (obj[key] as? String) ?? "" }
        func bool(_ key: String, _ fallback: Bool = false) -> Bool { (obj[key] as? Bool) ?? fallback }

        switch type {
        case "tap":
            let x = int("x"); let y = int("y")
            return (x >= 0 && y >= 0) ? .tap(x: x, y: y) : nil
        case "tapmark", "tap_mark":
            let id = int("markId")
            return id > 0 ? .tapMark(id: id) : nil
        case "doubleclick", "double_click":
            let x = int("x"); let y = int("y")
            return (x >= 0 && y >= 0) ? .doubleClick(x: x, y: y) : nil
        case "doubleclickmark", "double_click_mark":
            let id = int("markId")
            return id > 0 ? .doubleClickMark(id: id) : nil
        case "rightclick", "right_click":
            let x = int("x"); let y = int("y")
            return (x >= 0 && y >= 0) ? .rightClick(x: x, y: y) : nil
        case "rightclickmark", "right_click_mark":
            let id = int("markId")
            return id > 0 ? .rightClickMark(id: id) : nil
        case "longpress", "long_press":
            let x = int("x"); let y = int("y")
            return (x >= 0 && y >= 0) ? .longPress(x: x, y: y, durationMs: int("durationMs", 800)) : nil
        case "longpressmark", "long_press_mark":
            let id = int("markId")
            return id > 0 ? .longPressMark(id: id, durationMs: int("durationMs", 800)) : nil
        case "swipe":
            let x1 = int("x1"); let y1 = int("y1"); let x2 = int("x2"); let y2 = int("y2")
            return (x1 >= 0 && y1 >= 0 && x2 >= 0 && y2 >= 0)
                ? .swipe(x1: x1, y1: y1, x2: x2, y2: y2, durationMs: int("durationMs", 300))
                : nil
        case "scroll":
            let x = int("x"); let y = int("y")
            return (x >= 0 && y >= 0)
                ? .scroll(x: x, y: y, deltaX: int("deltaX", 0), deltaY: int("deltaY", 0))
                : nil
        case "typetext", "type_text", "type":
            let text = str("text")
            return text.isEmpty ? nil : .typeText(text: text, submit: bool("submit"))
        case "keypress", "key_press", "key":
            let keys = (obj["keys"] as? [String]) ?? []
            return keys.isEmpty ? nil : .keyPress(keys: keys.map { $0.lowercased() })
        case "switchtotarget", "switch_to_target":
            return .switchToTarget
        case "wait":
            return .wait(ms: min(max(int("ms", 500), 0), 60_000))
        case "noop", "":
            return .noop
        default:
            return nil
        }
    }
}
