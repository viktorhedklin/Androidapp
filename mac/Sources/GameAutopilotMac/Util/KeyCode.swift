import CoreGraphics

/// Hand-rolled CGKeyCode lookup so ActionDispatcher doesn't need to import
/// Carbon/HIToolbox from a plain SPM target. Values are the standard US
/// keyboard hardware-position constants (stable, unchanged for years --
/// the same table every keyboard-remapping tool on macOS uses).
///
/// Named per the closed key-name vocabulary documented in the brain's
/// system prompt (see Brain/PromptBuilder.swift): modifiers
/// (cmd/shift/option/ctrl), specials (escape/return/tab/space/delete/
/// arrows/f1-f20), else a literal single character.
enum KeyCode {
    static let table: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "equal": 0x18, "9": 0x19, "7": 0x1A, "minus": 0x1B, "8": 0x1C,
        "0": 0x1D, "rightbracket": 0x1E, "o": 0x1F, "u": 0x20,
        "leftbracket": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26,
        "quote": 0x27, "k": 0x28, "semicolon": 0x29, "backslash": 0x2A,
        "comma": 0x2B, "slash": 0x2C, "n": 0x2D, "m": 0x2E, "period": 0x2F,
        "tab": 0x30, "space": 0x31, "grave": 0x32, "delete": 0x33,
        "escape": 0x35, "return": 0x24, "enter": 0x24,
        "command": 0x37, "cmd": 0x37,
        "shift": 0x38,
        "capslock": 0x39,
        "option": 0x3A, "alt": 0x3A,
        "control": 0x3B, "ctrl": 0x3B,
        "rightshift": 0x3C, "rightoption": 0x3D, "rightcontrol": 0x3E,
        "function": 0x3F, "fn": 0x3F,
        "f17": 0x40, "volumeup": 0x48, "volumedown": 0x49, "mute": 0x4A,
        "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f3": 0x63, "f8": 0x64,
        "f9": 0x65, "f11": 0x67, "f13": 0x69, "f16": 0x6A, "f14": 0x6B,
        "f10": 0x6D, "f12": 0x6F, "f15": 0x71,
        "help": 0x72, "home": 0x73, "pageup": 0x74, "forwarddelete": 0x75,
        "f4": 0x76, "end": 0x77, "f2": 0x78, "pagedown": 0x79, "f1": 0x7A,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E
    ]

    static func code(for name: String) -> CGKeyCode? {
        table[name.lowercased()]
    }

    /// Names ActionDispatcher folds into CGEventFlags on the "real" key's
    /// events rather than posting as standalone keydown/keyup pairs.
    static let modifierNames: Set<String> = ["cmd", "command", "shift", "option", "alt", "control", "ctrl"]

    static func flag(for name: String) -> CGEventFlags? {
        switch name.lowercased() {
        case "cmd", "command": return .maskCommand
        case "shift": return .maskShift
        case "option", "alt": return .maskAlternate
        case "control", "ctrl": return .maskControl
        default: return nil
        }
    }
}
