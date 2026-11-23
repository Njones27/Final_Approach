/// One thing the on-device technical check measures in a photo.
public enum CheckKind: String, CaseIterable, Codable, Sendable {
    case horizon
    case sharpness
    case exposure
    case noise
    case heatHaze
    case framing

    public var displayName: String {
        switch self {
        case .horizon: "Level horizon"
        case .sharpness: "Sharpness"
        case .exposure: "Exposure"
        case .noise: "Noise"
        case .heatHaze: "Heat haze"
        case .framing: "Framing"
        }
    }
}

/// The score one check gave a photo, from 0 to 100.
public struct CheckResult: Equatable, Codable, Sendable {
    public let kind: CheckKind
    public let score: Double

    /// Returns nil when the score is outside 0 to 100.
    public init?(kind: CheckKind, score: Double) {
        guard (0...100).contains(score) else { return nil }
        self.kind = kind
        self.score = score
    }
}

/// A technical check sorted for display. The checks that need work come
/// first, weakest first, because the photographer should fix those first.
public struct TechnicalCheckReport: Equatable, Sendable {
    /// Checks under the passing score, weakest first.
    public let needsWork: [CheckResult]
    /// Checks at or above the passing score, strongest first.
    public let passed: [CheckResult]

    /// - Parameters:
    ///   - results: One result per check that ran.
    ///   - passingScore: The lowest score that counts as passed. It is data,
    ///     so it can be tuned without a release.
    public init(results: [CheckResult], passingScore: Double) {
        needsWork = results
            .filter { $0.score < passingScore }
            .sorted { $0.score < $1.score }
        passed = results
            .filter { $0.score >= passingScore }
            .sorted { $0.score > $1.score }
    }

    /// The weighted average of every check, or nil when no check ran.
    ///
    /// A check with no entry in `weights` counts once. A negative weight
    /// counts as zero.
    public func overallScore(weights: [CheckKind: Double] = [:]) -> Double? {
        var total = 0.0
        var weightSum = 0.0
        for result in needsWork + passed {
            let weight = max(weights[result.kind] ?? 1, 0)
            total += result.score * weight
            weightSum += weight
        }
        guard weightSum > 0 else { return nil }
        return total / weightSum
    }
}
