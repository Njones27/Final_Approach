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

    /// True when at least one check ran and none needs work. A photo has to
    /// pass before it can enter voting.
    public var isPassed: Bool {
        needsWork.isEmpty && !passed.isEmpty
    }

    /// How far the overall score would rise if one check reached `target`.
    /// It is zero when that check did not run or already scores that high.
    ///
    /// The weights mean the same as in `overallScore(weights:)`.
    public func overallGain(
        raising kind: CheckKind,
        to target: Double,
        weights: [CheckKind: Double] = [:]
    ) -> Double {
        let results = needsWork + passed
        guard let result = results.first(where: { $0.kind == kind }), result.score < target else {
            return 0
        }
        let weightSum = results.reduce(0.0) { $0 + max(weights[$1.kind] ?? 1, 0) }
        guard weightSum > 0 else { return 0 }
        return (target - result.score) * max(weights[kind] ?? 1, 0) / weightSum
    }
}

/// What to do about a check that needs work.
public struct FixAdvice: Equatable, Sendable {
    /// A verb and an object, such as "Straighten the horizon".
    public let title: String
    /// What the check saw, in one sentence.
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

/// One check's score with the words that explain it.
public struct CheckOutcome: Equatable, Sendable {
    public let result: CheckResult
    /// What the check saw, and how to fix it when it needs work.
    public let detail: String
    /// The fix to suggest, or nil when the check passed.
    public let advice: FixAdvice?

    public init(result: CheckResult, detail: String, advice: FixAdvice?) {
        self.result = result
        self.detail = detail
        self.advice = advice
    }
}

/// Scores a photo's measurements and writes the feedback for each check.
public enum TechnicalCheckEngine {
    /// One outcome for each check that could run, in the order of
    /// `CheckKind`. A check with no measurement is left out.
    ///
    /// - Parameters:
    ///   - measurements: What the device measured in the photo.
    ///   - rules: The values that turn measurements into scores.
    ///   - passingScore: The lowest score that counts as passed.
    ///   - camera: The photo's camera settings, used to make the feedback
    ///     specific.
    public static func outcomes(
        for measurements: PhotoMeasurements,
        rules: CheckRules,
        passingScore: Double,
        camera: CameraSettings? = nil
    ) -> [CheckOutcome] {
        [
            horizon(measurements, rules: rules, passingScore: passingScore),
            sharpness(measurements, rules: rules, passingScore: passingScore, camera: camera),
            exposure(measurements, rules: rules, passingScore: passingScore),
            framing(measurements, rules: rules, passingScore: passingScore),
        ].compactMap { $0 }
    }

    // MARK: Checks

    private static func horizon(
        _ measurements: PhotoMeasurements,
        rules: CheckRules,
        passingScore: Double
    ) -> CheckOutcome? {
        guard let tilt = measurements.tiltDegrees, tilt.isFinite, abs(tilt) <= rules.maximumTilt else {
            return nil
        }
        let score = rules.tilt.score(for: abs(tilt))
        if score >= passingScore {
            return outcome(.horizon, score, "The horizon is level.")
        }
        let angle = "\(CameraSettings.trimmed(abs(tilt)))°"
        return outcome(
            .horizon,
            score,
            "The horizon tilts about \(angle). Rotate the crop to level it.",
            FixAdvice(title: "Straighten the horizon", detail: "It tilts about \(angle).")
        )
    }

    private static func sharpness(
        _ measurements: PhotoMeasurements,
        rules: CheckRules,
        passingScore: Double,
        camera: CameraSettings?
    ) -> CheckOutcome? {
        guard let sharpness = measurements.sharpness else { return nil }
        let score = rules.sharpness.score(for: sharpness)
        if score >= passingScore {
            return outcome(.sharpness, score, "The aircraft is sharp.")
        }
        let seen = if let shutter = camera?.shutterText {
            "The aircraft is soft at \(shutter)."
        } else {
            "The aircraft is soft."
        }
        return outcome(
            .sharpness,
            score,
            "\(seen) Try a faster shutter speed.",
            FixAdvice(title: "Use a faster shutter", detail: seen)
        )
    }

    private static func exposure(
        _ measurements: PhotoMeasurements,
        rules: CheckRules,
        passingScore: Double
    ) -> CheckOutcome? {
        let highlights = measurements.blownHighlights.map { rules.clipping.score(for: $0) }
        let shadows = measurements.crushedShadows.map { rules.clipping.score(for: $0) }
        guard let score = [highlights, shadows].compactMap({ $0 }).min() else { return nil }
        if score >= passingScore {
            return outcome(.exposure, score, "Highlights and shadows both hold detail.")
        }
        // The worse of the two is the one to fix. Highlights win a tie
        // because detail lost to white cannot be brought back.
        if let highlights, highlights <= (shadows ?? 100) {
            return outcome(
                .exposure,
                score,
                "Bright parts of the aircraft are blown out. Lower the exposure.",
                FixAdvice(title: "Lower the exposure", detail: "Bright parts of the aircraft lose detail.")
            )
        }
        return outcome(
            .exposure,
            score,
            "Dark parts of the aircraft are crushed to black. Raise the exposure.",
            FixAdvice(title: "Raise the exposure", detail: "Dark parts of the aircraft lose detail.")
        )
    }

    private static func framing(
        _ measurements: PhotoMeasurements,
        rules: CheckRules,
        passingScore: Double
    ) -> CheckOutcome? {
        guard let subject = measurements.subject else { return nil }
        let edges = subject.edgesTouched(margin: rules.edgeMargin)
        let sizeScore = rules.subjectSize.score(for: subject.area)
        let score = edges.isEmpty ? sizeScore : min(sizeScore, rules.cutOffScore)
        if score >= passingScore {
            return outcome(.framing, score, "The aircraft is well placed in the frame.")
        }
        if !edges.isEmpty {
            let seen = switch edges.count {
            case 1: "The aircraft is cut off at the \(edges[0].rawValue) edge."
            case 2: "The aircraft is cut off at the \(edges[0].rawValue) and \(edges[1].rawValue) edges."
            default: "The aircraft does not fit in the frame."
            }
            return outcome(
                .framing,
                score,
                "\(seen) Zoom out a little.",
                FixAdvice(title: "Keep the whole aircraft in frame", detail: seen)
            )
        }
        let percent = max(1, Int((subject.area * 100).rounded()))
        let seen = "The aircraft fills only \(percent)% of the frame."
        return outcome(
            .framing,
            score,
            "\(seen) Get closer or crop tighter.",
            FixAdvice(title: "Fill more of the frame", detail: seen)
        )
    }

    /// Builds an outcome, keeping the score inside 0 to 100.
    private static func outcome(
        _ kind: CheckKind,
        _ score: Double,
        _ detail: String,
        _ advice: FixAdvice? = nil
    ) -> CheckOutcome? {
        guard let result = CheckResult(kind: kind, score: min(max(score, 0), 100)) else { return nil }
        return CheckOutcome(result: result, detail: detail, advice: advice)
    }
}
