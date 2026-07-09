import AppKit
import CoreGraphics
import Foundation

/// Draws translucent numbered rectangles on top of a copy of the captured
/// image. The numbers correspond to MarkBox.id; the brain returns these
/// ids via {"type":"tapMark","markId":N} instead of raw pixel coordinates.
/// Mirrors vision/SetOfMarksOverlay.kt (Android Canvas -> CoreGraphics).
enum SetOfMarksOverlay {
    static func annotate(_ image: CGImage, marks: [MarkBox]) -> CGImage {
        guard !marks.isEmpty else { return image }

        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Deliberately NOT flipping the CTM here: CGContext.draw(_:in:)
        // already orients a CGImage correctly in a context's native
        // (bottom-left origin, Y-up) space -- adding our own flip on top
        // would turn the base screenshot upside down. MarkBox coordinates
        // are top-left-origin/Y-down (matching AX/CGEvent/screenshot pixel
        // space), so each shape below converts its own Y explicitly
        // (contextY = imageHeight - pixelSpaceY) instead of touching the CTM.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let strokeWidth = max(2.0, Double(width) / 480.0)
        let fontSize = max(14.0, Double(width) / 60.0)
        let pad = max(3.0, Double(width) / 300.0)
        let h = Double(height)

        context.setLineWidth(strokeWidth)
        context.setStrokeColor(CGColor(red: 0.31, green: 0.86, blue: 0.47, alpha: 0.9))
        for m in marks {
            let rect = CGRect(x: Double(m.left), y: h - Double(m.bottom),
                               width: Double(m.width), height: Double(m.height))
            context.stroke(rect)
        }

        // This context is genuinely un-flipped (native Quartz Y-up), so
        // tell AppKit's text system exactly that.
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]

        for m in marks {
            let attributed = NSAttributedString(string: "\(m.id)", attributes: attrs)
            let textSize = attributed.size()
            let labelHeight = textSize.height + pad * 2

            // Label sits just above the mark's top edge, in image space --
            // i.e. its context-space Y starts at the mark's converted top
            // and extends further upward (larger Y) by its own height.
            // Clamp so a mark near the top of the frame doesn't push the
            // label off-canvas.
            let labelBottomInContext = min(h - Double(m.top), h - labelHeight)
            let bgRect = CGRect(
                x: Double(m.left),
                y: labelBottomInContext,
                width: textSize.width + pad * 2,
                height: labelHeight
            )
            NSColor.black.withAlphaComponent(0.78).setFill()
            bgRect.fill()
            attributed.draw(at: CGPoint(x: bgRect.origin.x + pad, y: bgRect.origin.y + pad))
        }

        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage() ?? image
    }
}
