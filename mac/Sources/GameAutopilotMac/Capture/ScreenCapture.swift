import CoreGraphics
import Foundation
import ScreenCaptureKit

/// One-shot per-tick screen capture via ScreenCaptureKit's
/// SCScreenshotManager (macOS 14+) -- a poll-per-tick loop, so the
/// one-shot API is the right fit, not the continuous SCStream API.
actor ScreenCapture {
    struct Target: Equatable {
        /// nil => whole-display fallback (used for fullscreen apps/games,
        /// whose window may not be reliably enumerable/capturable while
        /// running in its own Space).
        let windowID: CGWindowID?
        let displayID: CGDirectDisplayID
        let bundleIdentifier: String?
        let title: String
    }

    private(set) var currentTarget: Target?

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts the system Screen Recording permission dialog if not
    /// already granted. Call this explicitly from a user-initiated
    /// "Grant Screen Recording Access" button rather than relying on
    /// SCShareableContent enumeration to implicitly trigger it.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Enumerates on-screen windows as capture targets. Requires Screen
    /// Recording permission to already be granted -- callers should gate
    /// the picker UI behind `hasPermission()`.
    static func listCapturableTargets() async throws -> [Target] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let mainDisplayID = content.displays.first?.displayID ?? CGMainDisplayID()
        return content.windows.compactMap { window -> Target? in
            guard let app = window.owningApplication,
                  window.isOnScreen,
                  window.frame.width > 40,
                  window.frame.height > 40
            else { return nil }
            let title = (window.title?.isEmpty == false) ? window.title! : app.applicationName
            return Target(
                windowID: window.windowID,
                displayID: mainDisplayID,
                bundleIdentifier: app.bundleIdentifier,
                title: title
            )
        }
    }

    func setTarget(_ target: Target) {
        currentTarget = target
    }

    func clearTarget() {
        currentTarget = nil
    }

    /// Captures one frame of the current target. Returns nil on any
    /// failure -- a soft-fail mirroring Android's captureLatest(); callers
    /// treat a nil frame as "skip this tick," not a fatal error.
    func captureImage() async -> CGImage? {
        guard let target = currentTarget else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return nil
        }

        let filter: SCContentFilter
        if let windowID = target.windowID,
           let window = content.windows.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else if let display = content.displays.first(where: { $0.displayID == target.displayID }) {
            // Fullscreen fallback: cross-Space window capture has a history
            // of returning blank frames on some macOS versions, so a target
            // that can't be found as an enumerable window falls back to
            // capturing its whole display instead.
            filter = SCContentFilter(display: display, excludingWindows: [])
        } else {
            return nil
        }

        let config = SCStreamConfiguration()
        config.showsCursor = false
        // Default output size does NOT auto-match the window/display --
        // must set explicitly (accounting for Retina backing scale) or
        // frames come back downscaled, hurting OCR/mark accuracy.
        let scale = filter.pointPixelScale
        config.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        config.height = max(1, Int((filter.contentRect.height * scale).rounded()))

        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
