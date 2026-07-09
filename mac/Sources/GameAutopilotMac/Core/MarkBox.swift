import Foundation

/// Where a candidate tap target came from -- mirrors core/MarkBox.kt's
/// MarkSource on the Android side. Accessibility marks win over OCR marks
/// on overlap (see Perception/CandidateExtractor.swift).
enum MarkSource {
    case a11y
    case ocr
}

/// A numbered candidate tap target drawn on the annotated screenshot
/// ("set of marks" prompting) and referenced by id in the brain's
/// tapMark/longPressMark/etc. actions. Pixel coordinates, top-left origin
/// -- matches AXUIElement, CGEvent, and CGImage pixel space, no flipping
/// needed here (contrast with Vision's OCR boxes, which are flipped
/// before they ever become a MarkBox -- see OcrEngine.swift).
struct MarkBox: Equatable {
    let id: Int
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int
    let source: MarkSource
    let label: String

    var cx: Int { (left + right) / 2 }
    var cy: Int { (top + bottom) / 2 }
    var width: Int { right - left }
    var height: Int { bottom - top }
    var area: Int64 { Int64(width) * Int64(height) }

    func iou(_ other: MarkBox) -> Float {
        let ix1 = max(left, other.left)
        let iy1 = max(top, other.top)
        let ix2 = min(right, other.right)
        let iy2 = min(bottom, other.bottom)
        if ix2 <= ix1 || iy2 <= iy1 { return 0 }
        let inter = Int64(ix2 - ix1) * Int64(iy2 - iy1)
        let union = area + other.area - inter
        if union <= 0 { return 0 }
        return Float(Double(inter) / Double(union))
    }

    func withId(_ newId: Int) -> MarkBox {
        MarkBox(id: newId, left: left, top: top, right: right, bottom: bottom, source: source, label: label)
    }
}
