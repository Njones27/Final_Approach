/// One side of a photo.
public enum FrameEdge: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case top
    case bottom
}

/// A rectangle inside a photo. Each value is a fraction of the photo's width
/// or height, and the origin is the top left corner.
public struct FrameRegion: Equatable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    /// The part of the rectangle that lies inside the photo. Returns nil
    /// when a value is not a number or nothing of the rectangle is inside.
    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { return nil }
        let left = max(x, 0)
        let top = max(y, 0)
        let right = min(x + width, 1)
        let bottom = min(y + height, 1)
        guard right > left, bottom > top else { return nil }
        self.x = left
        self.y = top
        self.width = right - left
        self.height = bottom - top
    }

    private init(uncheckedX x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The whole photo.
    public static let whole = FrameRegion(uncheckedX: 0, y: 0, width: 1, height: 1)

    /// The share of the photo the rectangle covers, from 0 to 1.
    public var area: Double {
        width * height
    }

    /// The sides of the photo the rectangle reaches. A side counts when the
    /// rectangle comes closer to it than `margin`, which is a fraction of the
    /// photo's width or height.
    public func edgesTouched(margin: Double) -> [FrameEdge] {
        var edges: [FrameEdge] = []
        if x <= margin { edges.append(.left) }
        if x + width >= 1 - margin { edges.append(.right) }
        if y <= margin { edges.append(.top) }
        if y + height >= 1 - margin { edges.append(.bottom) }
        return edges
    }
}

/// The brightness of every pixel in a photo, from 0 for black to 255 for
/// white. Rows run from the top of the photo to the bottom.
///
/// The app fills this in from the image. The measuring is done here so it
/// can be tested without an Apple framework.
public struct LuminanceGrid: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    /// Returns nil unless there is exactly one value for each pixel.
    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The columns and rows a region covers.
    func bounds(of region: FrameRegion) -> (columns: Range<Int>, rows: Range<Int>) {
        let left = min(Int((region.x * Double(width)).rounded(.down)), width - 1)
        let right = min(Int(((region.x + region.width) * Double(width)).rounded(.up)), width)
        let top = min(Int((region.y * Double(height)).rounded(.down)), height - 1)
        let bottom = min(Int(((region.y + region.height) * Double(height)).rounded(.up)), height)
        return (left..<max(right, left + 1), top..<max(bottom, top + 1))
    }

    /// How much fine detail a region holds, as the variance of the Laplacian.
    /// A sharp subject gives a high value and a soft one a low value.
    ///
    /// Returns nil when the region is smaller than three pixels on a side.
    public func laplacianVariance(in region: FrameRegion = .whole) -> Double? {
        let (columns, rows) = bounds(of: region)
        guard columns.count >= 3, rows.count >= 3 else { return nil }
        var sum = 0.0
        var sumOfSquares = 0.0
        pixels.withUnsafeBufferPointer { buffer in
            for row in (rows.lowerBound + 1)..<(rows.upperBound - 1) {
                let rowStart = row * width
                for column in (columns.lowerBound + 1)..<(columns.upperBound - 1) {
                    let index = rowStart + column
                    let neighbors = Int(buffer[index - width]) + Int(buffer[index + width])
                        + Int(buffer[index - 1]) + Int(buffer[index + 1])
                    let response = Double(neighbors - 4 * Int(buffer[index]))
                    sum += response
                    sumOfSquares += response * response
                }
            }
        }
        let count = Double((columns.count - 2) * (rows.count - 2))
        let mean = sum / count
        return max(sumOfSquares / count - mean * mean, 0)
    }

    /// The share of a region that is at least as bright as `level`, from 0
    /// to 1.
    public func share(atOrAbove level: UInt8, in region: FrameRegion = .whole) -> Double {
        share(in: region) { $0 >= level }
    }

    /// The share of a region that is at least as dark as `level`, from 0
    /// to 1.
    public func share(atOrBelow level: UInt8, in region: FrameRegion = .whole) -> Double {
        share(in: region) { $0 <= level }
    }

    private func share(in region: FrameRegion, where matches: (UInt8) -> Bool) -> Double {
        let (columns, rows) = bounds(of: region)
        var matching = 0
        pixels.withUnsafeBufferPointer { buffer in
            for row in rows {
                let rowStart = row * width
                for column in columns where matches(buffer[rowStart + column]) {
                    matching += 1
                }
            }
        }
        return Double(matching) / Double(columns.count * rows.count)
    }
}

/// What the device measured in a photo, before any score is given.
///
/// Every value is optional because a measurement can fail. A photo of an
/// aircraft against open sky has no horizon to measure, for example.
public struct PhotoMeasurements: Equatable, Codable, Sendable {
    /// Where the aircraft is in the photo.
    public let subject: FrameRegion?
    /// The variance of the Laplacian over the aircraft.
    public let sharpness: Double?
    /// The share of the aircraft's area that is blown out to white, from 0
    /// to 1.
    public let blownHighlights: Double?
    /// The share of the aircraft's area that is crushed to black, from 0
    /// to 1.
    public let crushedShadows: Double?
    /// How far the horizon is from level, in degrees. The sign gives the
    /// direction.
    public let tiltDegrees: Double?

    public init(
        subject: FrameRegion? = nil,
        sharpness: Double? = nil,
        blownHighlights: Double? = nil,
        crushedShadows: Double? = nil,
        tiltDegrees: Double? = nil
    ) {
        self.subject = subject
        self.sharpness = sharpness
        self.blownHighlights = blownHighlights
        self.crushedShadows = crushedShadows
        self.tiltDegrees = tiltDegrees
    }

    /// A photo in which nothing could be measured.
    public static let none = PhotoMeasurements()

    /// Measures sharpness and exposure from the photo's brightness. They are
    /// measured over the aircraft, or over the whole photo when the aircraft
    /// was not found.
    public init(grid: LuminanceGrid, subject: FrameRegion?, tiltDegrees: Double?, rules: CheckRules) {
        let region = subject ?? .whole
        self.init(
            subject: subject,
            sharpness: grid.laplacianVariance(in: region),
            blownHighlights: grid.share(atOrAbove: rules.highlightLevel, in: region),
            crushedShadows: grid.share(atOrBelow: rules.shadowLevel, in: region),
            tiltDegrees: tiltDegrees
        )
    }
}
