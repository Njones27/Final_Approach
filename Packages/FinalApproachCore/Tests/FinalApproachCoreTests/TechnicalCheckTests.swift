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
