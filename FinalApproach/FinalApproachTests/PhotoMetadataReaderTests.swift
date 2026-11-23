import FinalApproachCore
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import FinalApproach

@MainActor
struct PhotoMetadataReaderTests {
    @Test func readsCameraSettingsTimeAndPlaceFromAPhotoFile() throws {
        let exif: [CFString: Any] = [
            kCGImagePropertyExifFNumber: 7.1,
            kCGImagePropertyExifExposureTime: 1.0 / 640,
            kCGImagePropertyExifFocalLength: 400,
            kCGImagePropertyExifISOSpeedRatings: [200],
            kCGImagePropertyExifLensModel: "RF100-500mm F4.5-7.1 L IS USM",
            kCGImagePropertyExifDateTimeOriginal: "2026:11:14 17:42:05",
        ]
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "Canon",
            kCGImagePropertyTIFFModel: "Canon EOS R5",
        ]
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 33.6215,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 84.399,
            kCGImagePropertyGPSLongitudeRef: "W",
            kCGImagePropertyGPSImgDirection: 135.5,
            kCGImagePropertyGPSImgDirectionRef: "T",
        ]
        let data = try makeJPEG(properties: [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff,
            kCGImagePropertyGPSDictionary: gps,
        ])

        let photo = try #require(PhotoMetadataReader.importPhoto(from: data))
        let camera = try #require(photo.metadata.camera)
        #expect(camera.cameraName == "Canon EOS R5")
        #expect(camera.lensModel == "RF100-500mm F4.5-7.1 L IS USM")
        #expect(camera.focalLengthText == "400 mm")
        #expect(camera.apertureText == "f/7.1")
        #expect(camera.shutterText == "1/640 s")
        #expect(camera.isoText == "ISO 200")

        let capturedAt = try #require(photo.metadata.capturedAt)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: capturedAt)
        #expect(parts.year == 2026)
        #expect(parts.month == 11)
        #expect(parts.day == 14)
        #expect(parts.hour == 17)
        #expect(parts.minute == 42)

        let coordinate = try #require(photo.metadata.coordinate)
        #expect(abs(coordinate.latitude - 33.6215) < 0.001)
        #expect(abs(coordinate.longitude + 84.399) < 0.001)

        let heading = try #require(photo.metadata.heading)
        #expect(abs(heading - 135.5) < 0.01)
    }

    @Test func aPhotoWithNoMetadataStillImports() throws {
        let data = try makeJPEG(properties: [:])
        let photo = try #require(PhotoMetadataReader.importPhoto(from: data))
        #expect(photo.metadata.capturedAt == nil)
        #expect(photo.metadata.coordinate == nil)
    }

    @Test func dataThatIsNotAnImageDoesNotImport() {
        let photo = PhotoMetadataReader.importPhoto(from: Data("not an image".utf8))
        #expect(photo?.id == nil)
    }

    @Test func anUnreadableCaptureTimeGivesNoDate() {
        #expect(PhotoMetadataReader.captureDate(fromExif: "yesterday") == nil)
    }

    /// Writes a small gray JPEG that carries the given ImageIO properties.
    private func makeJPEG(properties: [CFString: Any]) throws -> Data {
        let size = CGSize(width: 16, height: 16)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let cgImage = try #require(image.cgImage)
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
