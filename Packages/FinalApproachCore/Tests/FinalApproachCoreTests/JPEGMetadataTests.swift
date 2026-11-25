import Foundation
import Testing

@testable import FinalApproachCore

struct JPEGMetadataTests {
    private func segment(_ marker: UInt8, _ payload: String) -> [UInt8] {
        let body = Array(payload.utf8)
        let length = body.count + 2
        return [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + body
    }

    private let scan: [UInt8] = [0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9]

    private func jpeg(_ segments: [UInt8]...) -> Data {
        Data([0xFF, 0xD8] + segments.flatMap { $0 } + scan)
    }

    @Test func exifXMPAndIPTCAreTakenOutAndTheRestIsKept() {
        let profile = segment(0xE2, "ICC_PROFILE\0color")
        let table = segment(0xDB, "table")
        let image = jpeg(
            segment(0xE0, "JFIF\0"),
            segment(0xE1, "Exif\0\0gps"),
            segment(0xE1, "http://ns.adobe.com/xap/1.0/\0GPSLatitude"),
            profile,
            segment(0xED, "Photoshop 3.0\0city"),
            table
        )

        #expect(JPEGMetadata.removed(from: image) == jpeg(segment(0xE0, "JFIF\0"), profile, table))
    }

    @Test func aCleanImageComesBackAsItWas() {
        let image = jpeg(segment(0xE0, "JFIF\0"), segment(0xDB, "table"))

        #expect(JPEGMetadata.removed(from: image) == image)
    }

    @Test func thePictureDataIsNeverRead() {
        // Bytes that look like an Exif block after the scan starts are picture data.
        let image = Data([0xFF, 0xD8] + segment(0xDB, "table") + [0xFF, 0xDA, 0x00, 0x02] + segment(0xE1, "Exif\0\0"))

        #expect(JPEGMetadata.removed(from: image) == image)
    }

    @Test func bytesThatAreNotAWholeJPEGGiveNothing() {
        #expect(JPEGMetadata.removed(from: Data("not a picture".utf8)) == nil)
        #expect(JPEGMetadata.removed(from: Data()) == nil)
        // The header ends before the picture data begins.
        #expect(JPEGMetadata.removed(from: Data([0xFF, 0xD8] + segment(0xE0, "JFIF\0"))) == nil)
        // A block that says it is longer than the file.
        #expect(JPEGMetadata.removed(from: Data([0xFF, 0xD8, 0xFF, 0xE1, 0x40, 0x00, 0x01])) == nil)
    }
}
