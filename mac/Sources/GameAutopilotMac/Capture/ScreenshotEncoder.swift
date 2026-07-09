import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales to a max edge and JPEG-encodes to base64 for the brain's
/// image payload. Mirrors capture/ScreenshotEncoder.kt + util/BitmapUtils.kt.
///
/// scaleToMaxEdge is a plain draw+makeImage round trip with no manual CTM
/// flip -- unlike SetOfMarksOverlay, nothing here draws geometry in a
/// different coordinate convention, so CGContext.draw(_:in:) orienting the
/// image correctly by default is exactly what's wanted; no flip needed.
enum ScreenshotEncoder {
    static let defaultMaxEdge = 1024
    static let defaultJpegQuality: CGFloat = 0.8

    static func encode(_ image: CGImage, maxEdge: Int = defaultMaxEdge, jpegQuality: CGFloat = defaultJpegQuality) -> String? {
        let scaled = scaleToMaxEdge(image, maxEdge: maxEdge)
        guard let data = jpegData(scaled, quality: jpegQuality) else { return nil }
        return data.base64EncodedString()
    }

    static func scaleToMaxEdge(_ image: CGImage, maxEdge: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let longest = max(width, height)
        guard longest > maxEdge else { return image }

        let scale = Double(maxEdge) / Double(longest)
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }

    private static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
