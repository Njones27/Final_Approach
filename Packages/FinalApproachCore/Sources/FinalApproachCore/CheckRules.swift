/// Turns a measurement into a score from 0 to 100.
///
/// The curve is a list of points. A measurement between two points gets a
/// score on the straight line between them, and a measurement past either
/// end gets the score of that end. The points are data, so a check can be
/// tuned without a release.
public struct ScoreCurve: Equatable, Codable, Sendable {
    public struct Point: Equatable, Codable, Sendable {
        public let value: Double
        public let score: Double

        public init(value: Double, score: Double) {
            self.value = value
            self.score = score
        }
    }

    public let points: [Point]

    /// Returns nil unless there is at least one point, the values rise from
    /// one point to the next, and every score is from 0 to 100.
    public init?(_ points: [Point]) {
        guard !points.isEmpty else { return nil }
        for point in points {
            guard point.value.isFinite, (0...100).contains(point.score) else { return nil }
        }
        for (earlier, later) in zip(points, points.dropFirst()) {
            guard later.value > earlier.value else { return nil }
        }
        self.points = points
    }

    /// Builds a curve from pairs of a measurement and its score.
    public init?(pairs: [(Double, Double)]) {
        self.init(pairs.map { Point(value: $0.0, score: $0.1) })
    }

    /// The score for a measurement.
    public func score(for value: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        // A measurement that is not a number gets the lowest score on the
        // curve, so a broken reading never passes a check.
        guard !value.isNaN else { return points.map(\.score).min() ?? 0 }
        if value <= first.value { return first.score }
        if value >= last.value { return last.score }
        for (lower, upper) in zip(points, points.dropFirst()) where value <= upper.value {
            let progress = (value - lower.value) / (upper.value - lower.value)
            return lower.score + (upper.score - lower.score) * progress
        }
        return last.score
    }
}

/// The values that turn a photo's measurements into check scores.
///
/// Every value is data so it can come from the backend and be tuned without
/// a release.
public struct CheckRules: Equatable, Codable, Sendable {
    /// The checks that run. A check that is not listed is never scored, so
    /// one that is not yet trustworthy can stay off.
    public let enabledChecks: Set<CheckKind>
    /// The longest side, in pixels, of the copy of the photo that is
    /// measured. The sharpness curves only hold at this size.
    public let analysisPixelSize: Int
    /// Scores the variance of the Laplacian over the aircraft's own pixels.
    public let sharpnessOnMask: ScoreCurve
    /// Scores the variance of the Laplacian over a box around the aircraft.
    /// The box holds some sky, so the numbers run lower than on a mask.
    public let sharpnessInBox: ScoreCurve
    /// Scores how many degrees the horizon is from level.
    public let tilt: ScoreCurve
    /// The largest angle, in degrees, that is still read as a horizon. A
    /// larger one is taken to be something else, and the check does not run.
    public let maximumTilt: Double
    /// A pixel at least this bright counts as blown out.
    public let highlightLevel: UInt8
    /// A pixel at least this dark counts as crushed.
    public let shadowLevel: UInt8
    /// Scores the share of the aircraft that is blown out, from 0 to 1.
    public let highlights: ScoreCurve
    /// Scores the share of the aircraft that is crushed, from 0 to 1. It is
    /// looser than the highlight curve, because a dark aircraft in shade has
    /// large black areas that are correct.
    public let shadows: ScoreCurve
    /// Scores the share of the photo the aircraft fills, from 0 to 1. The
    /// score is expected to rise with the share.
    public let subjectSize: ScoreCurve
    /// An aircraft closer to a side of the photo than this share of its
    /// width or height counts as reaching that side.
    public let edgeMargin: Double
    /// An aircraft that fills at least this share of the photo is taken to
    /// be a deliberate close-up, so reaching a side is not held against it.
    public let closeUpArea: Double
    /// The highest framing score an aircraft that is cut off can get.
    public let cutOffScore: Double

    public init(
        enabledChecks: Set<CheckKind>,
        analysisPixelSize: Int,
        sharpnessOnMask: ScoreCurve,
        sharpnessInBox: ScoreCurve,
        tilt: ScoreCurve,
        maximumTilt: Double,
        highlightLevel: UInt8,
        shadowLevel: UInt8,
        highlights: ScoreCurve,
        shadows: ScoreCurve,
        subjectSize: ScoreCurve,
        edgeMargin: Double,
        closeUpArea: Double,
        cutOffScore: Double
    ) {
        self.enabledChecks = enabledChecks
        self.analysisPixelSize = analysisPixelSize
        self.sharpnessOnMask = sharpnessOnMask
        self.sharpnessInBox = sharpnessInBox
        self.tilt = tilt
        self.maximumTilt = maximumTilt
        self.highlightLevel = highlightLevel
        self.shadowLevel = shadowLevel
        self.highlights = highlights
        self.shadows = shadows
        self.subjectSize = subjectSize
        self.edgeMargin = edgeMargin
        self.closeUpArea = closeUpArea
        self.cutOffScore = cutOffScore
    }
}
