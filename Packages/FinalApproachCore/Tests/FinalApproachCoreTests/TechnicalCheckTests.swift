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
    let centered = FrameRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5)!

    func check(
        _ measurements: PhotoMeasurements,
        rules: CheckRules = TestRules.rules,
        camera: CameraSettings? = nil
    ) -> [CheckOutcome] {
        TechnicalCheckEngine.outcomes(for: measurements, rules: rules, passingScore: 75, camera: camera)
    }

    @Test func aTiltedSoftShotFailsWithFeedbackNamingBothProblems() throws {
        let measurements = PhotoMeasurements(
            subject: centered,
            subjectSource: .mask,
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
        #expect(sharpness.detail == "The aircraft is soft. Check the focus and try a faster shutter speed.")
        #expect(sharpness.advice == FixAdvice(title: "Check focus and shutter speed", detail: "The aircraft is soft."))
    }

    @Test func aCleanShotPassesEveryCheckWithNoFixes() {
        let measurements = PhotoMeasurements(
            subject: centered,
            subjectSource: .mask,
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

    @Test func aCheckThatIsTurnedOffNeverRuns() {
        let measurements = PhotoMeasurements(
            subject: centered,
            subjectSource: .mask,
            sharpness: 40,
            blownHighlights: 0,
            crushedShadows: 0,
            tiltDegrees: 2
        )
        let withoutHorizon = TestRules.rules(enabling: [.sharpness, .exposure, .framing])
        #expect(check(measurements, rules: withoutHorizon).map(\.result.kind) == [.sharpness, .exposure, .framing])
        #expect(check(measurements, rules: TestRules.rules(enabling: [])).isEmpty)
    }

    @Test func softnessAtASlowShutterSuggestsAFasterOne() throws {
        let camera = CameraSettings(exposureTime: 1.0 / 250)
        let measurements = PhotoMeasurements(subject: centered, subjectSource: .mask, sharpness: 40)
        let outcome = try #require(check(measurements, camera: camera).first { $0.result.kind == .sharpness })
        #expect(outcome.detail == "The aircraft is soft at 1/250 s. Try a faster shutter speed.")
        #expect(outcome.advice == FixAdvice(title: "Use a faster shutter", detail: "The aircraft is soft at 1/250 s."))
    }

    @Test func softnessAtAFastShutterIsNotPutDownToTheShutter() throws {
        let measurements = PhotoMeasurements(subject: centered, subjectSource: .mask, sharpness: 40)
        for time in [1.0 / 1000, 1.0 / 2000] {
            let camera = CameraSettings(exposureTime: time)
            let outcome = try #require(check(measurements, camera: camera).first { $0.result.kind == .sharpness })
            #expect(outcome.detail.hasSuffix(
                "That is fast enough to freeze it, so check the focus, heat haze, or a heavy crop."
            ))
            #expect(outcome.advice?.title == "Check focus and haze")
        }
        let fast = try #require(
            check(measurements, camera: CameraSettings(exposureTime: 1.0 / 2000))
                .first { $0.result.kind == .sharpness }
        )
        #expect(fast.advice?.detail == "The aircraft is soft at 1/2000 s.")
    }

    @Test func aLowContrastAircraftCanPassOnDetailForItsContrast() throws {
        // 60 is soft on the raw curve. Against a contrast of 300 it is a
        // fifth, which is sharp for an aircraft with so little to measure.
        let matte = PhotoMeasurements(subject: centered, subjectSource: .mask, sharpness: 60, contrast: 300)
        let outcome = try #require(check(matte).first { $0.result.kind == .sharpness })
        #expect(abs(outcome.result.score - 80) < 0.001)
        #expect(outcome.advice == nil)
        #expect(outcome.detail == "The aircraft is sharp.")
    }

    @Test func aHighContrastAircraftWithLittleDetailIsStillSoft() throws {
        let soft = PhotoMeasurements(subject: centered, subjectSource: .mask, sharpness: 60, contrast: 3000)
        let outcome = try #require(check(soft).first { $0.result.kind == .sharpness })
        #expect(outcome.result.score == 45)
        #expect(outcome.advice != nil)
    }

    @Test func contrastNeverLowersASharpScore() throws {
        let sharp = PhotoMeasurements(subject: centered, subjectSource: .mask, sharpness: 300, contrast: 30000)
        let outcome = try #require(check(sharp).first { $0.result.kind == .sharpness })
        #expect(outcome.result.score == 100)
    }

    @Test func aFlatAircraftIsScoredOnTheRawCurveAlone() throws {
        let flat = PhotoMeasurements(subject: centered, subjectSource: .mask, sharpness: 60, contrast: 0)
        let outcome = try #require(check(flat).first { $0.result.kind == .sharpness })
        #expect(outcome.result.score == 45)
    }

    @Test func contrastIsNotUsedInsideABox() throws {
        let inBox = PhotoMeasurements(subject: centered, subjectSource: .box, sharpness: 20, contrast: 20)
        let outcome = try #require(check(inBox).first { $0.result.kind == .sharpness })
        #expect(outcome.result.score == 37.5)
    }

    @Test func sharpnessInABoxIsScoredOnItsOwnCurve() throws {
        // 60 is soft on the aircraft's own pixels and sharp inside a box,
        // because a box holds sky that pulls the number down.
        let onMask = PhotoMeasurements(subject: centered, subjectSource: .mask, sharpness: 60)
        let inBox = PhotoMeasurements(subject: centered, subjectSource: .box, sharpness: 60)
        let maskScore = try #require(check(onMask).first { $0.result.kind == .sharpness }).result.score
        let boxScore = try #require(check(inBox).first { $0.result.kind == .sharpness }).result.score
        #expect(maskScore == 45)
        #expect(boxScore == 81.25)
    }

    @Test func sharpnessDoesNotRunWhenNoAircraftWasFound() {
        #expect(check(PhotoMeasurements(sharpness: 400)).isEmpty)
    }

    @Test func tiltFeedbackGivesTheAngleWithoutItsSign() throws {
        let outcome = try #require(check(PhotoMeasurements(tiltDegrees: -1.8)).first)
        #expect(outcome.result.kind == .horizon)
        #expect(outcome.detail == "The horizon tilts about 1.8°. Rotate the crop to level it.")
    }

    @Test func anAnglePastTheLimitIsNotAHorizon() {
        #expect(check(PhotoMeasurements(tiltDegrees: 25)).isEmpty)
    }

    @Test func blownHighlightsAndCrushedShadowsGetDifferentAdvice() throws {
        let bright = try #require(
            check(PhotoMeasurements(subject: centered, subjectSource: .mask, blownHighlights: 0.1, crushedShadows: 0))
                .first { $0.result.kind == .exposure }
        )
        #expect(bright.advice?.title == "Lower the exposure")
        #expect(bright.detail == "Bright parts of the aircraft are blown out. Lower the exposure.")

        let dark = try #require(
            check(PhotoMeasurements(subject: centered, subjectSource: .mask, blownHighlights: 0, crushedShadows: 0.5))
                .first { $0.result.kind == .exposure }
        )
        #expect(dark.result.score == 37.5)
        #expect(dark.advice?.title == "Raise the exposure")
        #expect(dark.detail == "Dark parts of the aircraft are crushed to black. Raise the exposure.")
    }

    @Test func shadowsAreScoredMoreLooselyThanHighlights() throws {
        // A tenth of the aircraft blown out fails. A tenth crushed passes.
        let measurements = PhotoMeasurements(
            subject: centered,
            subjectSource: .box,
            blownHighlights: 0,
            crushedShadows: 0.1
        )
        let crushed = try #require(check(measurements).first)
        #expect(crushed.result.kind == .exposure)
        #expect(crushed.result.score == 90)
        #expect(crushed.advice == nil)
    }

    @Test func exposureDoesNotRunWhenNoAircraftWasFound() {
        // Blown pixels in a photo with no aircraft are as likely to be
        // clouds, so they are not held against it.
        #expect(check(PhotoMeasurements(blownHighlights: 0.1, crushedShadows: 0)).isEmpty)
    }

    @Test func anAircraftAtTheEdgeIsCutOff() throws {
        let atLeftEdge = try #require(FrameRegion(x: 0, y: 0.25, width: 0.5, height: 0.5))
        let outcome = try #require(check(PhotoMeasurements(subject: atLeftEdge, subjectSource: .mask)).first)
        #expect(outcome.result.kind == .framing)
        #expect(outcome.result.score == 40)
        #expect(outcome.detail == "The aircraft is cut off at the left edge. Zoom out a little.")
        #expect(outcome.advice?.title == "Keep the whole aircraft in frame")
    }

    @Test func aCloseUpThatFillsTheFrameIsNotCutOff() throws {
        let outcome = try #require(check(PhotoMeasurements(subject: .whole, subjectSource: .mask)).first)
        #expect(outcome.result.score == 100)
        #expect(outcome.advice == nil)
    }

    @Test func aWideAircraftAcrossTheFrameDoesNotFit() throws {
        let acrossTheBottom = try #require(FrameRegion(x: 0, y: 0.5, width: 1, height: 0.5))
        let outcome = try #require(check(PhotoMeasurements(subject: acrossTheBottom, subjectSource: .mask)).first)
        #expect(outcome.detail == "The aircraft does not fit in the frame. Zoom out a little.")
    }

    @Test func aSmallAircraftShouldFillMoreOfTheFrame() throws {
        let small = try #require(FrameRegion(x: 0.375, y: 0.375, width: 0.25, height: 0.125))
        let outcome = try #require(check(PhotoMeasurements(subject: small, subjectSource: .mask)).first)
        #expect(outcome.detail == "The aircraft fills only 3% of the frame. Get closer or crop tighter.")
        #expect(outcome.advice?.title == "Fill more of the frame")
    }

    @Test func framingDoesNotRunOnABoxAlone() {
        let small = FrameRegion(x: 0.375, y: 0.375, width: 0.25, height: 0.125)
        #expect(check(PhotoMeasurements(subject: small, subjectSource: .box)).isEmpty)
    }

    @Test func nothingMeasuredGivesNoOutcomes() {
        #expect(check(.none).isEmpty)
    }
}
