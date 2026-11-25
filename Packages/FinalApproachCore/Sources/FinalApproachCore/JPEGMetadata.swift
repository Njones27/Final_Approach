import Foundation

/// Takes the written metadata out of a JPEG file.
///
/// Other users see a posted image, and it must not say where it was taken.
/// The backend refuses a post whose image has an Exif block it cannot vouch
/// for, an XMP block that names a position, or an IPTC block. This removes
/// every Exif, XMP, and IPTC block, so the image the app keeps and sends
/// always passes. The color profile is kept, so the picture looks the same.
public enum JPEGMetadata {
    private static let startOfImage: UInt8 = 0xD8
    private static let endOfImage: UInt8 = 0xD9
    private static let startOfScan: UInt8 = 0xDA
    /// APP1 holds Exif and XMP.
    private static let app1: UInt8 = 0xE1
    /// APP13 holds IPTC.
    private static let app13: UInt8 = 0xED

    /// Returns the JPEG with its Exif, XMP, and IPTC blocks taken out, or
    /// nil when the bytes are not a JPEG that reaches its picture data.
    public static func removed(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == startOfImage else { return nil }

        var kept: [UInt8] = [0xFF, startOfImage]
        kept.reserveCapacity(bytes.count)
        var offset = 2
        while offset + 4 <= bytes.count {
            guard bytes[offset] == 0xFF else { return nil }
            let marker = bytes[offset + 1]
            // A marker may be padded with extra 0xFF bytes.
            if marker == 0xFF {
                offset += 1
                continue
            }
            // The picture data starts here. Everything from here on is kept as it is.
            if marker == startOfScan {
                kept.append(contentsOf: bytes[offset...])
                return Data(kept)
            }
            if marker == endOfImage { return nil }
            // These markers stand alone, with no length after them.
            if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                kept.append(contentsOf: bytes[offset..<offset + 2])
                offset += 2
                continue
            }
            // The length counts its own two bytes.
            let length = Int(bytes[offset + 2]) * 256 + Int(bytes[offset + 3])
            let end = offset + 2 + length
            guard length >= 2, end <= bytes.count else { return nil }
            if marker != app1 && marker != app13 {
                kept.append(contentsOf: bytes[offset..<end])
            }
            offset = end
        }
        return nil
    }
}
