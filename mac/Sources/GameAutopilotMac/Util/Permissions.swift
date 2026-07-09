import AppKit
import Foundation

/// Checks + deep-links for the two TCC permissions this app needs.
/// Mirrors util/PermissionsUtil.kt. No Info.plist usage-description key
/// exists for either (unlike camera/mic) -- both are purely TCC-database
/// driven at runtime, checked here rather than declared anywhere.
enum Permissions {
    static func hasAccessibility() -> Bool {
        AccessibilityReader.isTrusted(promptIfNeeded: false)
    }

    static func hasScreenRecording() -> Bool {
        ScreenCapture.hasPermission()
    }

    static func openAccessibilitySettings() {
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func openPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
