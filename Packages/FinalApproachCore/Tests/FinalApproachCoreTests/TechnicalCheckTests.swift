import Testing

@testable import FinalApproachCore

@Suite struct TechnicalCheckTests {
    let results = [
        CheckResult(kind: .exposure, score: 90)!,
        CheckResult(kind: .horizon, score: 60)!,
        CheckResult(kind: .framing, score: 80)!,
        CheckResult(kind: .sharpness, score: 70)!,
        CheckResult(kind: .noise, score: 86)!,
        CheckResult(kind: .heatHaze, score: 82)!,
    ]

    @Test func rejectsScoresOutsideZeroToOneHundred() {
        #expect(CheckResult(kind: .noise, score: -1) == nil)
        #expect(CheckResult(kind: .noise, score: 100.5) == nil)
        #expect(CheckResult(kind: .noise, score: 0) != nil)
        #expect(CheckResult(kind: .noise, score: 100) != nil)
    }

    @Test func listsTheWeakestChecksFirst() {
        let report = TechnicalCheckReport(results: results, passingScore: 75)
        #expect(report.needsWork.map(\.kind) == [.horizon, .sharpness])
        #expect(report.passed.map(\.kind) == [.exposure, .noise, .heatHaze, .framing])
    }

    @Test func aScoreAtThePassingScorePasses() {
        let report = TechnicalCheckReport(results: results, passingScore: 80)
        #expect(report.passed.map(\.kind).contains(.framing))
        #expect(!report.needsWork.map(\.kind).contains(.framing))
    }

    @Test func overallScoreIsTheAverageByDefault() {
        let report = TechnicalCheckReport(results: results, passingScore: 75)
        #expect(report.overallScore() == 78)
    }

    @Test func overallScoreUsesTheWeightsItIsGiven() {
        let report = TechnicalCheckReport(
            results: [
                CheckResult(kind: .horizon, score: 60)!,
                CheckResult(kind: .exposure, score: 90)!,
            ],
            passingScore: 75
        )
        #expect(report.overallScore(weights: [.horizon: 3]) == 67.5)
        #expect(report.overallScore(weights: [.horizon: 0]) == 90)
        #expect(report.overallScore(weights: [.horizon: -2]) == 90)
    }

    @Test func overallScoreIsNilWhenNothingRan() {
        let report = TechnicalCheckReport(results: [], passingScore: 75)
        #expect(report.overallScore() == nil)
        #expect(report.overallScore(weights: [.horizon: 0]) == nil)
    }
}

@Suite struct TechnicalCheckGateTests {
    let results = [
        CheckResult(kind: .horizon, score: 60)!,
        CheckResult(kind: .exposure, score: 90)!,
    ]

    @Test func aPhotoPassesOnlyWhenNoCheckNeedsWork() {
        #expect(!TechnicalCheckReport(results: results, passingScore: 75).isPassed)
        #expect(TechnicalCheckReport(results: results, passingScore: 60).isPassed)
    }

    @Test func aPhotoWithNoChecksHasNotPassed() {
        #expect(!TechnicalCheckReport(results: [], passingScore: 75).isPassed)
    }

    @Test func aFixIsWorthItsShareOfTheOverallScore() {
        let report = TechnicalCheckReport(results: results, passingScore: 75)
        #expect(report.overallGain(raising: .horizon, to: 90) == 15)
        #expect(report.overallGain(raising: .horizon, to: 90, weights: [.horizon: 3]) == 22.5)
    }

    @Test func aFixIsWorthNothingWhenThereIsNothingToGain() {
        let report = TechnicalCheckReport(results: results, passingScore: 75)
        #expect(report.overallGain(raising: .exposure, to: 90) == 0)
        #expect(report.overallGain(raising: .noise, to: 90) == 0)
        #expect(report.overallGain(raising: .horizon, to: 90, weights: [.horizon: 0]) == 0)
    }
}

@Suite struct TechnicalCheckEngineTests {
    let rules = TestRules.rules
    let centered = FrameRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5)!

    func check(
        _ measurements: PhotoMeasurements,
        camera: CameraSettings? = nil
    ) -> [CheckOutcome] {
        TechnicalCheckEngine.outcomes(for: measurements, rules: rules, passingScore: 75, camera: camera)
    }

    @Test func aTiltedSoftShotFailsWithFeedbackNamingBothProblems() throws {
        let measurements = PhotoMeasurements(
            subject: centered,
            sharpness: 40,
            blownHighlights: 0,
            crushedShadows: 0,
            tiltDegrees: 2
        )
        let outcomes = check(measurements)
        #expect(outcomes.map(\.result.kind) == [.horizon, .sharpness, .exposure, .framing])

        let report = TechnicalCheckReport(results: outcomes.map(\.result), passingScore: 75)
        #expect(!report.isPassed)
        #expect(Set(report.needsWork.map(\.kind)) == [.horizon, .sharpness])

        let horizon = try #require(outcomes.first { $0.result.kind == .horizon })
        #expect(horizon.result.score == 56.25)
        #expect(horizon.detail == "The horizon tilts about 2°. Rotate the crop to level it.")
        #expect(horizon.advice == FixAdvice(title: "Straighten the horizon", detail: "It tilts about 2°."))

        let sharpness = try #require(outcomes.first { $0.result.kind == .sharpness })
        #expect(sharpness.detail == "The aircraft is soft. Try a faster shutter speed.")
        #expect(sharpness.advice?.title == "Use a faster shutter")
    }

    @Test func aCleanShotPassesEveryCheckWithNoFixes() {
        let measurements = PhotoMeasurements(
            subject: centered,
            sharpness: 400,
            blownHighlights: 0,
            crushedShadows: 0,
            tiltDegrees: 0.2
        )
        let outcomes = check(measurements)
        let report = TechnicalCheckReport(results: outcomes.map(\.result), passingScore: 75)
        #expect(report.isPassed)
        #expect(outcomes.allSatisfy { $0.advice == nil })
        #expect(outcomes.map(\.detail) == [
            "The horizon is level.",
            "The aircraft is sharp.",
            "Highlights and shadows both hold detail.",
            "The aircraft is well placed in the frame.",
        ])
    }

    @Test func softnessFeedbackNamesTheShutterSpeedWhenItIsKnown() throws {
        let camera = CameraSettings(exposureTime: 1.0 / 250)
        let outcome = try #require(check(PhotoMeasurements(sharpness: 40), camera: camera).first)
        #expect(outcome.detail == "The aircraft is soft at 1/250 s. Try a faster shutter speed.")
        #expect(outcome.advice?.detail == "The aircraft is soft at 1/250 s.")
    }

    @Test func tiltFeedbackGivesTheAngleWithoutItsSign() throws {
        let outcome = try #require(check(PhotoMeasurements(tiltDegrees: -1.8)).first)
        #expect(outcome.result.kind == .horizon)
        #expect(outcome.detail == "The horizon tilts about 1.8°. Rotate the crop to level it.")
    }

    @Test func theHorizonCheckDoesNotRunWithoutAHorizon() {
        #expect(check(PhotoMeasurements(sharpness: 400)).map(\.result.kind) == [.sharpness])
        // An angle past the limit is something else, such as a climbing aircraft.
        #expect(check(PhotoMeasurements(tiltDegrees: 25)).isEmpty)
    }

    @Test func blownHighlightsAndCrushedShadowsGetDifferentAdvice() throws {
        let bright = try #require(check(PhotoMeasurements(blownHighlights: 0.1, crushedShadows: 0)).first)
        #expect(bright.result.kind == .exposure)
        #expect(bright.advice?.title == "Lower the exposure")
        #expect(bright.detail == "Bright parts of the aircraft are blown out. Lower the exposure.")

        let dark = try #require(check(PhotoMeasurements(blownHighlights: 0, crushedShadows: 0.1)).first)
        #expect(dark.advice?.title == "Raise the exposure")
        #expect(dark.detail == "Dark parts of the aircraft are crushed to black. Raise the exposure.")
    }

    @Test func anAircraftAtTheEdgeIsCutOff() throws {
        let atLeftEdge = try #require(FrameRegion(x: 0, y: 0.25, width: 0.5, height: 0.5))
        let outcome = try #require(check(PhotoMeasurements(subject: atLeftEdge)).first)
        #expect(outcome.result.kind == .framing)
        #expect(outcome.result.score == 40)
        #expect(outcome.detail == "The aircraft is cut off at the left edge. Zoom out a little.")
        #expect(outcome.advice?.title == "Keep the whole aircraft in frame")
    }

    @Test func anAircraftThatFillsTheFrameDoesNotFit() throws {
        let outcome = try #require(check(PhotoMeasurements(subject: .whole)).first)
        #expect(outcome.detail == "The aircraft does not fit in the frame. Zoom out a little.")
    }

    @Test func aSmallAircraftShouldFillMoreOfTheFrame() throws {
        let small = try #require(FrameRegion(x: 0.375, y: 0.375, width: 0.25, height: 0.125))
        let outcome = try #require(check(PhotoMeasurements(subject: small)).first)
        #expect(outcome.detail == "The aircraft fills only 3% of the frame. Get closer or crop tighter.")
        #expect(outcome.advice?.title == "Fill more of the frame")
    }

    @Test func nothingMeasuredGivesNoOutcomes() {
        #expect(check(.none).isEmpty)
    }
}
