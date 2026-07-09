import Foundation

/// Everything one tick's capture produced -- mirrors core/ScreenSnapshot.kt.
/// `marks` is the exact table the brain saw and that ActionDispatcher must
/// resolve mark ids against, so a tapMark always resolves to the frame the
/// brain actually reasoned about even if a newer frame is captured before
/// the action is dispatched.
struct ScreenSnapshot {
    let width: Int
    let height: Int
    /// Bundle identifier of whichever app is actually frontmost right now.
    /// Compared against the loop's configured target to gate dispatch --
    /// mirrors Android's onlyActOnTargetPackage safety check.
    let frontmostBundleIdentifier: String?
    let ocrLines: [String]
    let a11yLines: [String]
    let marks: [MarkBox]
    let screenshotBase64Jpeg: String
    let perceptualHash: UInt64
}
