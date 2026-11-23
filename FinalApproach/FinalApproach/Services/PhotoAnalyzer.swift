import CoreGraphics
import CoreVideo
import FinalApproachCore
import UIKit
import Vision

/// Measures a photo on the device for the technical check. It finds the
/// aircraft with Vision and reads the brightness of the pixels. The scoring
/// of what it measures lives in the core package.
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
    ///
    /// The aircraft is found as a mask of its own pixels. When Vision gives
    /// no mask, a box around the most prominent object stands in for it.
    nonisolated static func measure(_ image: CGImage, rules: CheckRules) -> PhotoMeasurements {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let mask = subjectMask(using: handler)
        let box = mask == nil ? subjectBox(using: handler) : nil
        let tilt = rules.enabledChecks.contains(.horizon) ? horizonTilt(using: handler) : nil
        guard let grid = luminanceGrid(from: image, maxPixelSize: rules.analysisPixelSize) else {
            return PhotoMeasurements(tiltDegrees: tilt)
        }
        return PhotoMeasurements(grid: grid, mask: mask, fallbackBox: box, tiltDegrees: tilt, rules: rules)
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

    /// The pixels that belong to the foreground, which are taken to be the
    /// aircraft. A formation comes back as one mask that holds every
    /// aircraft. Returns nil when Vision finds no foreground.
    ///
    /// This request and the one for the box both fail in the iOS simulator,
    /// which cannot build their models, so a photo imported there is never
    /// scored. They run on a Mac and are expected to run on an iPhone.
    nonisolated private static func subjectMask(using handler: VNImageRequestHandler) -> SubjectMask? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
        } catch {
            logFailure("Finding the aircraft's outline", error)
            return nil
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            return nil
        }
        return mask(from: observation.instanceMask)
    }

    /// Reads Vision's instance mask, in which zero is the background and
    /// every other value is the number of an instance.
    nonisolated private static func mask(from buffer: CVPixelBuffer) -> SubjectMask? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        var isSubject: [Bool] = []
        isSubject.reserveCapacity(width * height)
        for row in 0..<height {
            let line = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                isSubject.append(line[column] != 0)
            }
        }
        return SubjectMask(width: width, height: height, isSubject: isSubject)
    }

    /// A box around the most prominent object in the image. It is only used
    /// when there is no mask, because it can miss wingtips, rotors, and the
    /// other aircraft in a formation.
    nonisolated private static func subjectBox(using handler: VNImageRequestHandler) -> FrameRegion? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        do {
            try handler.perform([request])
        } catch {
            logFailure("Finding the aircraft", error)
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
    /// Vision finds no horizon. The horizon check is off in the rules for
    /// now, because this reading follows the aircraft more often than a
    /// real horizon.
    nonisolated private static func horizonTilt(using handler: VNImageRequestHandler) -> Double? {
        let request = VNDetectHorizonRequest()
        do {
            try handler.perform([request])
        } catch {
            logFailure("Finding the horizon", error)
            return nil
        }
        guard let angle = request.results?.first?.angle else { return nil }
        return Double(angle) * 180 / .pi
    }

    /// A Vision request that fails gives no reading, which looks the same as
    /// a photo with nothing to find. Debug builds say which one it was.
    nonisolated private static func logFailure(_ step: String, _ error: any Error) {
        #if DEBUG
        print("PhotoAnalyzer: \(step) failed. \(error)")
        #endif
    }
}
