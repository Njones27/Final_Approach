import Testing

@testable import FinalApproachCore

@Suite struct TierThresholdsTests {
    let thresholds = TierThresholds(bronze: 50, silver: 65, gold: 80)!

    @Test func rejectsThresholdsThatAreOutOfOrderOrOutOfRange() {
        #expect(TierThresholds(bronze: 65, silver: 50, gold: 80) == nil)
        #expect(TierThresholds(bronze: 50, silver: 50, gold: 80) == nil)
        #expect(TierThresholds(bronze: 0, silver: 65, gold: 80) == nil)
        #expect(TierThresholds(bronze: 50, silver: 65, gold: 101) == nil)
        #expect(TierThresholds(bronze: 50, silver: 65, gold: 100) != nil)
    }

    @Test func aScoreEarnsTheHighestTierItReaches() {
        #expect(thresholds.tier(forScore: 0) == .logged)
        #expect(thresholds.tier(forScore: 49.9) == .logged)
        #expect(thresholds.tier(forScore: 50) == .bronze)
        #expect(thresholds.tier(forScore: 64.9) == .bronze)
        #expect(thresholds.tier(forScore: 65) == .silver)
        #expect(thresholds.tier(forScore: 80) == .gold)
        #expect(thresholds.tier(forScore: 100) == .gold)
    }

    @Test func eachTierStartsAtItsThreshold() {
        #expect(thresholds.lowerBound(of: .logged) == 0)
        #expect(thresholds.lowerBound(of: .bronze) == 50)
        #expect(thresholds.lowerBound(of: .silver) == 65)
        #expect(thresholds.lowerBound(of: .gold) == 80)
    }

    @Test func reportsThePointsNeededForTheNextTier() {
        let fromSilver = thresholds.nextTier(aboveScore: 71)
        #expect(fromSilver?.tier == .gold)
        #expect(fromSilver?.pointsNeeded == 9)

        let fromLogged = thresholds.nextTier(aboveScore: 20)
        #expect(fromLogged?.tier == .bronze)
        #expect(fromLogged?.pointsNeeded == 30)

        #expect(thresholds.nextTier(aboveScore: 83) == nil)
    }
}
