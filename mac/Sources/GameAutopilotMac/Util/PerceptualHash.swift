import CoreGraphics
import Foundation

/// Classic dHash: scale to 9x8 grayscale, compare adjacent columns -> 64-bit
/// hash. Mirrors util/PerceptualHash.kt -- used purely for relative
/// "did the screen change much since last tick" comparisons (the
/// stuck-state circuit breaker in Core/DecisionLoop.swift), not for
/// anything that needs to match the Android hash bit-for-bit.
enum PerceptualHash {
    static func dHash(_ image: CGImage) -> UInt64 {
        let width = 9
        let height = 8
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return 0 }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)

        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<height {
            var prev = buffer[y * width]
            for x in 1..<width {
                let cur = buffer[y * width + x]
                if cur > prev { hash |= (1 << bit) }
                bit += 1
                prev = cur
            }
        }
        return hash
    }

    static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
