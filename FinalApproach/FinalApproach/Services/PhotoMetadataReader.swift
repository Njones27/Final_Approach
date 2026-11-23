import FinalApproachCore
import Foundation
import ImageIO
import UIKit

/// What the app reads from a photo file before the user logs it.
struct PhotoMetadata {
    /// The camera settings, or nil when the photo carried none.
    let camera: CameraSettings?
    /// When the photo was taken, by the camera's clock.
    let capturedAt: Date?
    /// Where the photo was taken, when the file carries a location.
    let coordinate: Coordinate?
    /// The compass direction the camera pointed, in degrees, when the file
    /// carries one. A phone saves it and most cameras do not.
    var heading: Double? = nil

    static let empty = PhotoMetadata(camera: nil, capturedAt: nil, coordinate: nil)
}

/// A photo picked from the library, read and ready to be logged.
struct ImportedPhoto: Identifiable {
    let id: String
    /// A copy sized for the screen. The full file is not kept in memory.
    let image: UIImage
    let metadata: PhotoMetadata
    /// What the technical check measured in the photo. It stays empty until
    /// the photo has been measured.
    var measurements = PhotoMeasurements.none
    /// The text read off the photo, which may hold the registration. It
    /// stays empty until the photo has been read.
    var recognizedText: [RecognizedText] = []
}

/// Reads the image and its saved metadata from a photo file with ImageIO.
/// Everything stays on the device.
enum PhotoMetadataReader {
    /// The longest side, in pixels, of the copy kept for display.
    static let displayPixelSize = 2048

    /// Reads a photo file. Returns nil when the data is not an image.
    static func importPhoto(from data: Data) -> ImportedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = displayImage(from: source)
        else { return nil }
        return ImportedPhoto(
            id: "imported-\(UUID().uuidString)",
            image: image,
            metadata: metadata(from: source)
        )
    }

    /// Makes a copy of the image that is small enough to keep in memory and
    /// already turned the right way up.
    private static func displayImage(from source: CGImageSource) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: displayPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func metadata(from source: CGImageSource) -> PhotoMetadata {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .empty
        }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exifAux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        let camera = CameraSettings(
            cameraMake: tiff[kCGImagePropertyTIFFMake] as? String,
            cameraModel: tiff[kCGImagePropertyTIFFModel] as? String,
            lensModel: exif[kCGImagePropertyExifLensModel] as? String
                ?? exifAux[kCGImagePropertyExifAuxLensModel] as? String,
            focalLength: number(exif[kCGImagePropertyExifFocalLength]),
            aperture: number(exif[kCGImagePropertyExifFNumber]),
            exposureTime: number(exif[kCGImagePropertyExifExposureTime]),
            iso: (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        )

        return PhotoMetadata(
            camera: camera.isEmpty ? nil : camera,
            capturedAt: (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
                .flatMap { captureDate(fromExif: $0) },
            coordinate: coordinate(from: gps),
            heading: number(gps[kCGImagePropertyGPSImgDirection])
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// Turns the EXIF capture time into a date. EXIF saves the camera's clock
    /// with no time zone, so the time is read in the iPhone's time zone.
    static func captureDate(fromExif text: String) -> Date? {
        guard let timestamp = CaptureTimestamp(exif: text) else { return nil }
        var components = DateComponents()
        components.year = timestamp.year
        components.month = timestamp.month
        components.day = timestamp.day
        components.hour = timestamp.hour
        components.minute = timestamp.minute
        components.second = timestamp.second
        return Calendar(identifier: .gregorian).date(from: components)
    }

    /// Reads the location. EXIF saves each value as a positive number with a
    /// letter for the hemisphere.
    private static func coordinate(from gps: [CFString: Any]) -> Coordinate? {
        guard let latitude = number(gps[kCGImagePropertyGPSLatitude]),
              let longitude = number(gps[kCGImagePropertyGPSLongitude])
        else { return nil }
        let isSouth = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
        let isWest = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
        return Coordinate(
            latitude: isSouth ? -latitude : latitude,
            longitude: isWest ? -longitude : longitude
        )
    }
}
