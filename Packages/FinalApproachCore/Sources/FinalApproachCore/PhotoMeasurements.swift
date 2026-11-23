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

/// How the aircraft was found in a photo.
public enum SubjectSource: String, Codable, Sendable {
    /// A mask that marks the aircraft's own pixels.
    case mask
    /// A box around the most prominent object, used when no mask was found.
    /// It can miss wingtips, rotors, and the other aircraft in a formation.
    case box
}

/// The pixels of a photo that belong to the aircraft. Rows run from the top
/// of the photo to the bottom.
///
/// The mask can be smaller than the photo's brightness grid. A grid pixel
/// belongs to the aircraft when the mask pixel at the same place does.
public struct SubjectMask: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// One value for each mask pixel. It is true where the aircraft is.
    public let isSubject: [Bool]

    /// Returns nil unless there is exactly one value for each pixel.
    public init?(width: Int, height: Int, isSubject: [Bool]) {
        guard width > 0, height > 0, isSubject.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.isSubject = isSubject
    }

    /// The smallest rectangle that holds the aircraft, or nil when the mask
    /// marks nothing.
    public var boundingRegion: FrameRegion? {
        var left = width
        var right = -1
        var top = height
        var bottom = -1
        for row in 0..<height {
            let rowStart = row * width
            for column in 0..<width where isSubject[rowStart + column] {
                left = min(left, column)
                right = max(right, column)
                top = min(top, row)
                bottom = max(bottom, row)
            }
        }
        guard right >= left, bottom >= top else { return nil }
        return FrameRegion(
            x: Double(left) / Double(width),
            y: Double(top) / Double(height),
            width: Double(right - left + 1) / Double(width),
            height: Double(bottom - top + 1) / Double(height)
        )
    }

    /// For each column or row of a grid, the mask column or row at the same
    /// place.
    static func positions(from gridCount: Int, to maskCount: Int) -> [Int] {
        (0..<gridCount).map { index in
            min(maskCount - 1, (2 * index + 1) * maskCount / (2 * gridCount))
        }
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
    /// With a mask, only the pixels that belong to the aircraft are counted.
    /// Returns nil when the region is smaller than three pixels on a side or
    /// the mask marks nothing inside it.
    public func laplacianVariance(in region: FrameRegion = .whole, mask: SubjectMask? = nil) -> Double? {
        let (columns, rows) = bounds(of: region)
        guard columns.count >= 3, rows.count >= 3 else { return nil }
        let maskColumns = mask.map { SubjectMask.positions(from: width, to: $0.width) }
        let maskRows = mask.map { SubjectMask.positions(from: height, to: $0.height) }
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0
        pixels.withUnsafeBufferPointer { buffer in
            for row in (rows.lowerBound + 1)..<(rows.upperBound - 1) {
                let rowStart = row * width
                for column in (columns.lowerBound + 1)..<(columns.upperBound - 1) {
                    if let mask, let maskColumns, let maskRows,
                       !mask.isSubject[maskRows[row] * mask.width + maskColumns[column]] {
                        continue
                    }
                    let index = rowStart + column
                    let neighbors = Int(buffer[index - width]) + Int(buffer[index + width])
                        + Int(buffer[index - 1]) + Int(buffer[index + 1])
                    let response = Double(neighbors - 4 * Int(buffer[index]))
                    sum += response
                    sumOfSquares += response * response
                    count += 1
                }
            }
        }
        guard count > 0 else { return nil }
        let mean = sum / Double(count)
        return max(sumOfSquares / Double(count) - mean * mean, 0)
    }

    /// How much the brightness varies over a region, as its variance. A
    /// white aircraft with dark lettering gives a high value and a matte
    /// grey one a low value. With a mask, only the aircraft's pixels are
    /// counted. Returns nil when the mask marks nothing inside the region.
    public func luminanceVariance(in region: FrameRegion = .whole, mask: SubjectMask? = nil) -> Double? {
        let (columns, rows) = bounds(of: region)
        let maskColumns = mask.map { SubjectMask.positions(from: width, to: $0.width) }
        let maskRows = mask.map { SubjectMask.positions(from: height, to: $0.height) }
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0
        pixels.withUnsafeBufferPointer { buffer in
            for row in rows {
                let rowStart = row * width
                for column in columns {
                    if let mask, let maskColumns, let maskRows,
                       !mask.isSubject[maskRows[row] * mask.width + maskColumns[column]] {
                        continue
                    }
                    let value = Double(buffer[rowStart + column])
                    sum += value
                    sumOfSquares += value * value
                    count += 1
                }
            }
        }
        guard count > 0 else { return nil }
        let mean = sum / Double(count)
        return max(sumOfSquares / Double(count) - mean * mean, 0)
    }

    /// The share of a region that is at least as bright as `level`, from 0
    /// to 1. With a mask, only the aircraft's pixels are counted. Returns
    /// nil when the mask marks nothing inside the region.
    public func share(
        atOrAbove level: UInt8,
        in region: FrameRegion = .whole,
        mask: SubjectMask? = nil
    ) -> Double? {
        share(in: region, mask: mask) { $0 >= level }
    }

    /// The share of a region that is at least as dark as `level`, from 0
    /// to 1. With a mask, only the aircraft's pixels are counted. Returns
    /// nil when the mask marks nothing inside the region.
    public func share(
        atOrBelow level: UInt8,
        in region: FrameRegion = .whole,
        mask: SubjectMask? = nil
    ) -> Double? {
        share(in: region, mask: mask) { $0 <= level }
    }

    private func share(
        in region: FrameRegion,
        mask: SubjectMask?,
        where matches: (UInt8) -> Bool
    ) -> Double? {
        let (columns, rows) = bounds(of: region)
        let maskColumns = mask.map { SubjectMask.positions(from: width, to: $0.width) }
        let maskRows = mask.map { SubjectMask.positions(from: height, to: $0.height) }
        var matching = 0
        var count = 0
        pixels.withUnsafeBufferPointer { buffer in
            for row in rows {
                let rowStart = row * width
                for column in columns {
                    if let mask, let maskColumns, let maskRows,
                       !mask.isSubject[maskRows[row] * mask.width + maskColumns[column]] {
                        continue
                    }
                    count += 1
                    if matches(buffer[rowStart + column]) {
                        matching += 1
                    }
                }
            }
        }
        guard count > 0 else { return nil }
        return Double(matching) / Double(count)
    }
}

/// What the device measured in a photo, before any score is given.
///
/// Every value is optional because a measurement can fail. A photo in which
/// no aircraft is found has no sharpness to measure, for example.
public struct PhotoMeasurements: Equatable, Codable, Sendable {
    /// Where the aircraft is in the photo.
    public let subject: FrameRegion?
    /// How the aircraft was found. It is nil when it was not found.
    public let subjectSource: SubjectSource?
    /// The variance of the Laplacian over the aircraft.
    public let sharpness: Double?
    /// The variance of the brightness over the aircraft. Sharpness is read
    /// against it, because a matte aircraft has little detail to measure
    /// even when it is in focus.
    public let contrast: Double?
    /// The share of the aircraft that is blown out to white, from 0 to 1.
    public let blownHighlights: Double?
    /// The share of the aircraft that is crushed to black, from 0 to 1.
    public let crushedShadows: Double?
    /// How far the horizon is from level, in degrees. The sign gives the
    /// direction.
    public let tiltDegrees: Double?

    public init(
        subject: FrameRegion? = nil,
        subjectSource: SubjectSource? = nil,
        sharpness: Double? = nil,
        contrast: Double? = nil,
        blownHighlights: Double? = nil,
        crushedShadows: Double? = nil,
        tiltDegrees: Double? = nil
    ) {
        self.subject = subject
        // A source means nothing without a place, so the two stay together.
        self.subjectSource = subject == nil ? nil : subjectSource
        self.sharpness = sharpness
        self.contrast = contrast
        self.blownHighlights = blownHighlights
        self.crushedShadows = crushedShadows
        self.tiltDegrees = tiltDegrees
    }

    /// A photo in which nothing could be measured.
    public static let none = PhotoMeasurements()

    /// Measures sharpness and exposure from the photo's brightness.
    ///
    /// With a mask, only the aircraft's own pixels are measured. With only a
    /// box, everything inside the box is measured, which includes some sky.
    /// With neither, nothing is measured, because readings over a whole
    /// photo say little about the aircraft. Detail over a whole photo does
    /// not tell a sharp aircraft from a soft one, and blown pixels are as
    /// likely to be clouds.
    public init(
        grid: LuminanceGrid,
        mask: SubjectMask?,
        fallbackBox: FrameRegion?,
        tiltDegrees: Double?,
        rules: CheckRules
    ) {
        if let mask, let region = mask.boundingRegion {
            self.init(
                subject: region,
                subjectSource: .mask,
                sharpness: grid.laplacianVariance(mask: mask),
                contrast: grid.luminanceVariance(mask: mask),
                blownHighlights: grid.share(atOrAbove: rules.highlightLevel, mask: mask),
                crushedShadows: grid.share(atOrBelow: rules.shadowLevel, mask: mask),
                tiltDegrees: tiltDegrees
            )
        } else if let fallbackBox {
            self.init(
                subject: fallbackBox,
                subjectSource: .box,
                sharpness: grid.laplacianVariance(in: fallbackBox),
                contrast: grid.luminanceVariance(in: fallbackBox),
                blownHighlights: grid.share(atOrAbove: rules.highlightLevel, in: fallbackBox),
                crushedShadows: grid.share(atOrBelow: rules.shadowLevel, in: fallbackBox),
                tiltDegrees: tiltDegrees
            )
        } else {
            self.init(tiltDegrees: tiltDegrees)
        }
    }
}
