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
    /// `CheckKind`. A check that is turned off in the rules or has no
    /// measurement is left out.
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
        guard rules.enabledChecks.contains(.horizon),
              let tilt = measurements.tiltDegrees, tilt.isFinite, abs(tilt) <= rules.maximumTilt
        else { return nil }
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
        guard rules.enabledChecks.contains(.sharpness),
              let sharpness = measurements.sharpness,
              let source = measurements.subjectSource
        else { return nil }
        var score: Double
        switch source {
        case .mask:
            score = rules.sharpnessOnMask.score(for: sharpness)
            // A matte or dark aircraft has little detail to measure, so its
            // sharpness is also read against its own contrast.
            if let contrast = measurements.contrast, contrast > 0 {
                score = max(score, rules.sharpnessToContrast.score(for: sharpness / contrast))
            }
        case .box:
            score = rules.sharpnessInBox.score(for: sharpness)
        }
        if score >= passingScore {
            return outcome(.sharpness, score, "The aircraft is sharp.")
        }
        let words = softnessWords(camera: camera, rules: rules)
        return outcome(
            .sharpness,
            score,
            "\(words.seen) \(words.hint)",
            FixAdvice(title: words.title, detail: words.seen)
        )
    }

    /// What to say about a soft aircraft. A slow shutter is the likely
    /// cause only when the photo was not taken at a fast one.
    private static func softnessWords(
        camera: CameraSettings?,
        rules: CheckRules
    ) -> (seen: String, hint: String, title: String) {
        guard let time = camera?.exposureTime, let shutter = camera?.shutterText else {
            return (
                "The aircraft is soft.",
                "Check the focus and try a faster shutter speed.",
                "Check focus and shutter speed"
            )
        }
        if time <= rules.fastShutterTime {
            return (
                "The aircraft is soft at \(shutter).",
                "That is fast enough to freeze it, so check the focus, heat haze, or a heavy crop.",
                "Check focus and haze"
            )
        }
        return (
            "The aircraft is soft at \(shutter).",
            "Try a faster shutter speed.",
            "Use a faster shutter"
        )
    }

    private static func exposure(
        _ measurements: PhotoMeasurements,
        rules: CheckRules,
        passingScore: Double
    ) -> CheckOutcome? {
        // Exposure is judged on the aircraft, so it needs one to be found.
        guard rules.enabledChecks.contains(.exposure), measurements.subject != nil else { return nil }
        let highlights = measurements.blownHighlights.map { rules.highlights.score(for: $0) }
        let shadows = measurements.crushedShadows.map { rules.shadows.score(for: $0) }
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
        // Framing needs the aircraft's outline. A box alone can miss the
        // wingtips or the rest of a formation, which would read as cut off
        // or too small.
        guard rules.enabledChecks.contains(.framing),
              let subject = measurements.subject,
              measurements.subjectSource == .mask
        else { return nil }
        // An aircraft that fills the photo is a close-up, so reaching a side
        // is not held against it.
        let edges: [FrameEdge] = subject.area >= rules.closeUpArea
            ? []
            : subject.edgesTouched(margin: rules.edgeMargin)
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
