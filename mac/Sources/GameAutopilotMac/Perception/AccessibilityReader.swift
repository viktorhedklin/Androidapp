import ApplicationServices
import CoreGraphics
import Foundation

struct A11yClickable {
    let label: String
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int
}

struct A11yReadResult {
    let lines: [String]
    let clickables: [A11yClickable]
}

/// AXUIElement tree reader -- mirrors accessibility/NodeTreeReader.kt.
///
/// Unlike Android, there is no `isClickable` boolean; "clickable" is
/// inferred from AX role or the presence of a press action. Traversal is
/// time-boxed by BOTH node count and wall-clock deadline (Android only
/// needed the count cap) -- AX trees from privileged/hung/Electron-based
/// apps can genuinely hang a walk in ways Android's read never risked.
///
/// Expect this to often come back sparse or empty for native-rendered
/// games (raw Metal/SDL/Unity apps commonly expose a single opaque root
/// element with no children) -- OCR/vision carry more of the signal here
/// than on Android.
enum AccessibilityReader {
    static let maxNodes = 80
    static let traversalBudget: TimeInterval = 1.5

    // Literal role strings rather than the kAX*Role globals -- not all of
    // them (e.g. kAXLinkRole) are actually exposed by the ApplicationServices
    // Swift overlay, so this sidesteps that inconsistency entirely.
    private static let clickableRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXMenuItem",
        "AXLink",
        "AXTextField",
        "AXComboBox",
        "AXSlider"
    ]

    static func isTrusted(promptIfNeeded: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: NSDictionary = [key: promptIfNeeded]
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func read(pid: pid_t) -> A11yReadResult {
        let app = AXUIElementCreateApplication(pid)
        var lines: [String] = []
        var clickables: [A11yClickable] = []
        let deadline = Date().addingTimeInterval(traversalBudget)
        traverse(app, depth: 0, deadline: deadline, lines: &lines, clickables: &clickables)
        return A11yReadResult(lines: Array(lines.prefix(maxNodes)), clickables: clickables)
    }

    /// Currently keyboard-focused element, app-wide -- used by
    /// ActionDispatcher.typeText. More reliable than a recursive
    /// find-the-focused-node tree search (Android's approach) since this
    /// reflects real system-wide keyboard focus regardless of which app
    /// technically has it.
    static func focusedEditableElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
        guard err == .success, let value else { return nil }
        // Force downcast: `as?` here got flagged as "always succeeds" (Swift
        // can't statically fail a CFTypeRef -> AXUIElement conditional cast),
        // but plain `as` isn't valid Swift for a downcast either -- `as!` is
        // what the compiler actually wants.
        return (value as! AXUIElement)
    }

    static func setValue(_ element: AXUIElement, text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    // MARK: - Traversal

    private static func traverse(
        _ element: AXUIElement,
        depth: Int,
        deadline: Date,
        lines: inout [String],
        clickables: inout [A11yClickable]
    ) {
        if lines.count >= maxNodes || depth > 40 || Date() > deadline { return }

        let role = stringAttr(element, kAXRoleAttribute as CFString) ?? ""
        let title = stringAttr(element, kAXTitleAttribute as CFString) ?? ""
        let valueText = stringAttr(element, kAXValueAttribute as CFString) ?? ""
        let desc = stringAttr(element, kAXDescriptionAttribute as CFString) ?? ""

        let label: String
        if !title.isEmpty { label = title }
        else if !desc.isEmpty { label = desc }
        else if !valueText.isEmpty && valueText.count < 120 { label = valueText }
        else { label = "" }

        let isClickable = clickableRoles.contains(role) || hasPressAction(element)

        if let rect = boundsAttr(element), rect.width > 0, rect.height > 0 {
            let left = Int(rect.minX), top = Int(rect.minY)
            let right = Int(rect.maxX), bottom = Int(rect.maxY)

            if !label.isEmpty || isClickable {
                let displayLabel = (label.isEmpty ? "(unlabeled)" : String(label.prefix(80)))
                    .replacingOccurrences(of: "\n", with: " ")
                lines.append("[\(left),\(top),\(right),\(bottom)] click=\(isClickable ? "Y" : "N") role=\(role) \"\(displayLabel)\"")
            }
            if isClickable {
                clickables.append(A11yClickable(
                    label: label.isEmpty ? "(unlabeled)" : String(label.prefix(80)),
                    left: left, top: top, right: right, bottom: bottom
                ))
            }
        }

        guard let children = childrenAttr(element) else { return }
        for child in children {
            traverse(child, depth: depth + 1, deadline: deadline, lines: &lines, clickables: &clickables)
            if lines.count >= maxNodes || Date() > deadline { return }
        }
    }

    private static func hasPressAction(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let actions = names as? [String]
        else { return false }
        return actions.contains(kAXPressAction as String)
    }

    private static func stringAttr(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func boundsAttr(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue
        else { return nil }

        // Force downcast -- same reasoning as focusedEditableElement()
        // above. Position/size come wrapped in AXValue -- a raw cast to
        // CGPoint/CGSize would silently fail, must unwrap via
        // AXValueGetValue instead.
        let posAXValue = posValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posAXValue, .cgPoint, &point),
              AXValueGetValue(sizeAXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: point, size: size)
    }

    private static func childrenAttr(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement]
        else { return nil }
        return children
    }
}
