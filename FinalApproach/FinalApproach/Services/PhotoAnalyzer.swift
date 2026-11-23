import CoreGraphics
import FinalApproachCore
import UIKit
import Vision

/// Measures a photo on the device for the technical check. It finds the
/// aircraft and the horizon with Vision and reads the brightness of the
/// pixels. The scoring of what it measures lives in the core package.
///
/// Everything stays on the device.
enum PhotoAnalyzer {
    /// Measures a photo away from the main thread. A photo that cannot be
    /// read gives no measurements.
    static func measurements(for image: UIImage, rules: CheckRules) async -> PhotoMeasurements {
        guard let cgImage = image.cgImage else { return .none }
        return await Task.detached(priority: .userInitiated) {
            measure(cgImage, rules: rules)
        }.value
    }

    /// Measures an image that is already the right way up.
    nonisolated static func measure(_ image: CGImage, rules: CheckRules) -> PhotoMeasurements {
        let subject = subjectRegion(in: image)
        let tilt = horizonTilt(in: image)
        guard let grid = luminanceGrid(from: image, maxPixelSize: rules.analysisPixelSize) else {
            return PhotoMeasurements(subject: subject, tiltDegrees: tilt)
        }
        return PhotoMeasurements(grid: grid, subject: subject, tiltDegrees: tilt, rules: rules)
    }

    /// The brightness of the image, scaled down so its longest side is no
    /// more than `maxPixelSize`. Returns nil when the image cannot be drawn.
    nonisolated static func luminanceGrid(from image: CGImage, maxPixelSize: Int) -> LuminanceGrid? {
        let longestSide = max(image.width, image.height)
        guard longestSide > 0, maxPixelSize > 0 else { return nil }
        let scale = min(1, Double(maxPixelSize) / Double(longestSide))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return LuminanceGrid(width: width, height: height, pixels: pixels)
    }

    /// Where the most prominent object in the image is, which is taken to be
    /// the aircraft. Returns nil when Vision finds nothing that stands out.
    nonisolated private static func subjectRegion(in image: CGImage) -> FrameRegion? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let boxes = request.results?.first?.salientObjects?.map(\.boundingBox) ?? []
        guard let box = boxes.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }
        // Vision measures from the bottom left corner. The core package
        // measures from the top left.
        return FrameRegion(
            x: Double(box.minX),
            y: 1 - Double(box.maxY),
            width: Double(box.width),
            height: Double(box.height)
        )
    }

    /// How far the horizon is from level, in degrees. Returns nil when
    /// Vision finds no horizon.
    nonisolated private static func horizonTilt(in image: CGImage) -> Double? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let angle = request.results?.first?.angle else { return nil }
        return Double(angle) * 180 / .pi
    }
}
