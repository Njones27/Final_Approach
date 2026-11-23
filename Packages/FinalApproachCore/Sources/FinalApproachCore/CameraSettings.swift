/// The camera settings saved in a photo, with the wording used to show them.
///
/// Every field is optional because a photo may carry only some of them, or
/// none after an edit or an export.
public struct CameraSettings: Equatable, Codable, Sendable {
    public let cameraMake: String?
    public let cameraModel: String?
    public let lensModel: String?
    /// The focal length in millimeters.
    public let focalLength: Double?
    /// The f-number, such as 5.6.
    public let aperture: Double?
    /// The shutter time in seconds, such as 0.001 for 1/1000 s.
    public let exposureTime: Double?
    public let iso: Int?

    /// Values that cannot be real settings, such as an empty name or a zero
    /// or negative number, are stored as nil.
    public init(
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        focalLength: Double? = nil,
        aperture: Double? = nil,
        exposureTime: Double? = nil,
        iso: Int? = nil
    ) {
        self.cameraMake = Self.cleaned(cameraMake)
        self.cameraModel = Self.cleaned(cameraModel)
        self.lensModel = Self.cleaned(lensModel)
        self.focalLength = Self.positive(focalLength)
        self.aperture = Self.positive(aperture)
        self.exposureTime = Self.positive(exposureTime)
        self.iso = iso.flatMap { $0 > 0 ? $0 : nil }
    }

    /// True when the photo carried no camera settings at all.
    public var isEmpty: Bool {
        cameraName == nil && lensModel == nil && focalLength == nil
            && aperture == nil && exposureTime == nil && iso == nil
    }

    /// The camera as one name, such as "Canon EOS R5". The make is left out
    /// when the model already starts with the same word, which is how Canon
    /// and Nikon write their model names.
    public var cameraName: String? {
        guard let model = cameraModel else { return cameraMake }
        guard let make = cameraMake else { return model }
        let makeWord = make.split(separator: " ").first?.lowercased()
        let modelWord = model.split(separator: " ").first?.lowercased()
        if makeWord == modelWord { return model }
        return "\(make) \(model)"
    }

    /// The focal length, such as "400 mm".
    public var focalLengthText: String? {
        focalLength.map { "\(Self.trimmed($0)) mm" }
    }

    /// The aperture, such as "f/5.6".
    public var apertureText: String? {
        aperture.map { "f/\(Self.trimmed($0))" }
    }

    /// The shutter time, such as "1/1000 s" or "2.5 s".
    public var shutterText: String? {
        guard let exposureTime else { return nil }
        if exposureTime >= 1 {
            return "\(Self.trimmed(exposureTime)) s"
        }
        let denominator = (1 / exposureTime).rounded()
        guard denominator.isFinite, denominator < 1_000_000 else { return nil }
        return "1/\(Int(denominator)) s"
    }

    /// The sensitivity, such as "ISO 200".
    public var isoText: String? {
        iso.map { "ISO \($0)" }
    }

    /// A number with at most one decimal place and no trailing zero, so 400.0
    /// reads "400" and 5.6 reads "5.6".
    static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        var characters = Substring(text)
        while let first = characters.first, first.isWhitespace {
            characters.removeFirst()
        }
        while let last = characters.last, last.isWhitespace {
            characters.removeLast()
        }
        return characters.isEmpty ? nil : String(characters)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

/// The capture time saved in a photo, as the camera's clock read it.
///
/// EXIF stores this as text with no time zone, such as "2026:11:14 17:42:05".
/// The app turns it into a date. This type only reads the text.
public struct CaptureTimestamp: Equatable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let second: Int

    /// Reads an EXIF date and time. Returns nil when the text has another
    /// shape or a field is out of range.
    public init?(exif text: String) {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let date = parts[0].split(separator: ":").map { Int($0) }
        let time = parts[1].split(separator: ":").map { Int($0) }
        guard date.count == 3, time.count == 3,
              let year = date[0], let month = date[1], let day = date[2],
              let hour = time[0], let minute = time[1], let second = time[2],
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }
}
