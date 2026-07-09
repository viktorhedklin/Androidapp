import Foundation

/// Combines a11y clickable elements + OCR line boxes into a single mark
/// table. If a clickable a11y element and an OCR line overlap > 0.6 IoU,
/// the a11y one wins (richer label, already a genuine UI element). Sorted
/// by area DESC and truncated to maxMarks; ids assigned 1..N. Mirrors
/// vision/CandidateExtractor.kt.
///
/// Expect a11y marks to be sparser here than on Android -- many native
/// macOS games (raw Metal/SDL/Unity renderers) expose no meaningful AX
/// tree at all, so OCR frequently carries most of the signal.
enum CandidateExtractor {
    static func build(
        clickables: [A11yClickable],
        ocrBoxes: [OcrEngine.OcrLine],
        maxMarks: Int = 80,
        iouThreshold: Float = 0.6
    ) -> [MarkBox] {
        let a11yMarks = clickables.enumerated().map { i, c -> MarkBox in
            MarkBox(id: -1, left: c.left, top: c.top, right: c.right, bottom: c.bottom,
                    source: .a11y, label: c.label.isEmpty ? "a11y\(i)" : c.label)
        }
        let ocrMarks = ocrBoxes.map { o -> MarkBox in
            MarkBox(id: -1, left: o.left, top: o.top, right: o.right, bottom: o.bottom,
                    source: .ocr, label: o.text)
        }

        let filteredOcr = ocrMarks.filter { ocr in
            !a11yMarks.contains { $0.iou(ocr) > iouThreshold }
        }

        let combined = (a11yMarks + filteredOcr)
            .filter { $0.width > 4 && $0.height > 4 }
            .sorted { $0.area > $1.area }
            .prefix(maxMarks)

        return combined.enumerated().map { idx, m in m.withId(idx + 1) }
    }
}
