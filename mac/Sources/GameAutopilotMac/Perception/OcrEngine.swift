import CoreGraphics
import Foundation
import Vision

/// Vision-framework OCR, mirroring vision/OcrEngine.kt's ML Kit wrapper
/// shape (line-level text + bounding boxes).
enum OcrEngine {
    struct OcrLine {
        let text: String
        let left: Int
        let top: Int
        let right: Int
        let bottom: Int
    }

    struct OcrResult {
        let lines: [String]
        let boxes: [OcrLine]
    }

    /// Runs text recognition on `image`. Vision's `boundingBox` is
    /// normalized (0...1) with origin at the BOTTOM-LEFT, Y increasing
    /// upward -- the opposite of AX/CGEvent/screenshot pixel space
    /// (top-left origin, Y-down). This function does the flip internally
    /// so every OcrLine it returns is already in the same top-left-origin
    /// pixel space as MarkBox/AXUIElement/CGEvent -- callers never have to
    /// think about Vision's coordinate convention.
    static func recognize(_ image: CGImage) throws -> OcrResult {
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        var lines: [String] = []
        var boxes: [OcrLine] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            lines.append(text)

            let bb = observation.boundingBox // normalized, bottom-left origin, Y-up
            let left = Int((bb.minX * imageWidth).rounded())
            let right = Int((bb.maxX * imageWidth).rounded())
            let top = Int(((1 - bb.maxY) * imageHeight).rounded())
            let bottom = Int(((1 - bb.minY) * imageHeight).rounded())
            boxes.append(OcrLine(text: text, left: left, top: top, right: right, bottom: bottom))
        }
        return OcrResult(lines: lines, boxes: boxes)
    }
}
