import CoreGraphics
import FinalApproachCore
import UIKit
import Vision

/// Reads the text in a photo on the device, so a registration painted on
/// the aircraft can be found in it. Finding the registration in the text
/// lives in the core package.
///
/// Everything stays on the device.
enum RegistrationTextReader {
    /// How many ways of reading each piece of text to keep. A registration
    /// is not a word, so the right reading is often not the first.
    nonisolated static let readingsPerLine = 3

    /// Reads a photo away from the main thread. A photo that cannot be
    /// read gives no text.
    static func recognizedText(in image: UIImage) async -> [RecognizedText] {
        guard let cgImage = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            read(cgImage)
        }.value
    }

    /// Reads an image that is already the right way up.
    nonisolated static func read(_ image: CGImage) -> [RecognizedText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction turns a registration into the nearest word.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("RegistrationTextReader: Reading the text failed. \(error)")
            #endif
            return []
        }
        let observations = request.results ?? []
        return observations.flatMap { observation in
            observation.topCandidates(readingsPerLine).map { candidate in
                RecognizedText(text: candidate.string, confidence: Double(candidate.confidence))
            }
        }
    }
}
