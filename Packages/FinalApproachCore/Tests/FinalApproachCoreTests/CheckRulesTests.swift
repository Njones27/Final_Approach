import Testing

@testable import FinalApproachCore

/// Rules with round numbers, so the expected scores are easy to read.
enum TestRules {
    static let rules = CheckRules(
        analysisPixelSize: 1600,
        sharpness: ScoreCurve(pairs: [(0, 0), (100, 75), (300, 100)])!,
        tilt: ScoreCurve(pairs: [(0, 100), (1, 75), (5, 0)])!,
        maximumTilt: 10,
        highlightLevel: 250,
        shadowLevel: 5,
        clipping: ScoreCurve(pairs: [(0, 100), (0.02, 75), (0.2, 0)])!,
        subjectSize: ScoreCurve(pairs: [(0, 0), (0.1, 75), (0.3, 100)])!,
        edgeMargin: 0.01,
        cutOffScore: 40
    )
}

@Suite struct ScoreCurveTests {
    let curve = ScoreCurve(pairs: [(0, 0), (100, 75), (300, 100)])!

    @Test func rejectsACurveWithNoPoints() {
        #expect(ScoreCurve(pairs: []) == nil)
    }

    @Test func rejectsValuesThatDoNotRise() {
        #expect(ScoreCurve(pairs: [(0, 10), (0, 20)]) == nil)
        #expect(ScoreCurve(pairs: [(5, 10), (1, 20)]) == nil)
    }

    @Test func rejectsScoresOutsideZeroToOneHundred() {
        #expect(ScoreCurve(pairs: [(0, -1), (1, 50)]) == nil)
        #expect(ScoreCurve(pairs: [(0, 50), (1, 101)]) == nil)
    }

    @Test func scoresAMeasurementOnTheLineBetweenTwoPoints() {
        #expect(curve.score(for: 50) == 37.5)
        #expect(curve.score(for: 100) == 75)
        #expect(curve.score(for: 200) == 87.5)
    }

    @Test func holdsTheEndScoresPastEitherEnd() {
        #expect(curve.score(for: -5) == 0)
        #expect(curve.score(for: 1000) == 100)
    }

    @Test func aCurveCanFallAsTheMeasurementRises() {
        let tilt = ScoreCurve(pairs: [(0, 100), (2, 50)])!
        #expect(tilt.score(for: 1) == 75)
    }

    @Test func aReadingThatIsNotANumberGetsTheLowestScore() {
        #expect(curve.score(for: .nan) == 0)
    }

    @Test func aCurveWithOnePointGivesOneScore() {
        let flat = ScoreCurve(pairs: [(10, 60)])!
        #expect(flat.score(for: 0) == 60)
        #expect(flat.score(for: 99) == 60)
    }
}
