/// The camera settings other people may read beside a shown photo.
///
/// It holds the four numbers that say how the photo was taken, and never
/// the name of the camera or the lens. The backend keeps the same limits
/// and refuses a setting outside them. So a part that would be refused is
/// left out here, and the rest is still shown.
public struct ShownCamera: Equatable, Codable, Sendable {
    /// The focal length in millimeters.
    public let focalLength: Double?
    /// The f-number, such as 5.6.
    public let aperture: Double?
    /// The shutter time in seconds, such as 0.001 for 1/1000 s.
    public let exposureTime: Double?
    public let iso: Int?

    private enum CodingKeys: String, CodingKey {
        case focalLength
        case aperture
        case exposureTime
        case iso
    }

    public init(
        focalLength: Double? = nil,
        aperture: Double? = nil,
        exposureTime: Double? = nil,
        iso: Int? = nil
    ) {
        self.focalLength = focalLength
        self.aperture = aperture
        self.exposureTime = exposureTime
        self.iso = iso
    }

    /// The parts of a photo's settings that may be shown, or nil when none
    /// of them may.
    public init?(showing settings: CameraSettings, within limits: ShownCameraLimits) {
        self.init(
            focalLength: settings.focalLength.flatMap { limits.focalLength.contains($0) ? $0 : nil },
            aperture: settings.aperture.flatMap { limits.aperture.contains($0) ? $0 : nil },
            exposureTime: settings.exposureTime.flatMap { limits.exposureTime.contains($0) ? $0 : nil },
            iso: settings.iso.flatMap { limits.iso.contains($0) ? $0 : nil }
        )
        if isEmpty { return nil }
    }

    /// Reads the settings the backend sends back. A part that is missing,
    /// or that is not a number this type can hold, is read as nil, so one
    /// odd part never makes a whole answer unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focalLength = Self.number(in: container, for: .focalLength)
        aperture = Self.number(in: container, for: .aperture)
        exposureTime = Self.number(in: container, for: .exposureTime)
        let sensitivity = Self.number(in: container, for: .iso)
        iso = sensitivity.flatMap { Int(exactly: $0) }
    }

    /// True when no part is set.
    public var isEmpty: Bool {
        focalLength == nil && aperture == nil && exposureTime == nil && iso == nil
    }

    /// The same numbers with the wording used to show them, such as
    /// "400 mm" and "1/1000 s".
    public var settings: CameraSettings {
        CameraSettings(focalLength: focalLength, aperture: aperture, exposureTime: exposureTime, iso: iso)
    }

    /// The settings on one line, such as "400 mm, f/5.6, 1/1000 s, ISO 200",
    /// or nil when there is none to say.
    public var summary: String? {
        let worded = settings
        let parts = [worded.focalLengthText, worded.apertureText, worded.shutterText, worded.isoText]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func number(
        in container: KeyedDecodingContainer<CodingKeys>,
        for key: CodingKeys
    ) -> Double? {
        guard let value = try? container.decodeIfPresent(Double.self, forKey: key), value.isFinite else {
            return nil
        }
        return value
    }
}

/// The smallest and largest each shown camera setting may be. Anything
/// outside is not a real setting, and the backend refuses it.
public struct ShownCameraLimits: Equatable, Sendable {
    public let focalLength: ClosedRange<Double>
    public let aperture: ClosedRange<Double>
    public let exposureTime: ClosedRange<Double>
    public let iso: ClosedRange<Int>

    public init(
        focalLength: ClosedRange<Double>,
        aperture: ClosedRange<Double>,
        exposureTime: ClosedRange<Double>,
        iso: ClosedRange<Int>
    ) {
        self.focalLength = focalLength
        self.aperture = aperture
        self.exposureTime = exposureTime
        self.iso = iso
    }

    /// The limits the backend launched with.
    public static let launch = ShownCameraLimits(
        focalLength: 1...5000,
        aperture: 0.5...128,
        exposureTime: (1.0 / 1_000_000)...3600,
        iso: 1...10_000_000
    )
}
