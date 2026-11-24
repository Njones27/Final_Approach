import Foundation
import Testing

@testable import FinalApproachCore

@Suite struct VotingRulesTests {
    let rules = VotingRules.launch

    @Test func acceptsOnlyVotesOnTheScale() {
        #expect(rules.isValid(vote: 1))
        #expect(rules.isValid(vote: 5))
        #expect(!rules.isValid(vote: 0))
        #expect(!rules.isValid(vote: 6))
    }

    @Test func finalizesOnlyAfterTheWindowWithEnoughVotes() {
        let window = rules.windowSeconds
        #expect(!rules.canFinalize(voteCount: 4, secondsSinceOpened: window))
        #expect(!rules.canFinalize(voteCount: 5, secondsSinceOpened: window - 1))
        #expect(rules.canFinalize(voteCount: 5, secondsSinceOpened: window))
    }

    @Test func normalizesTheScaleOntoZeroToOneHundred() {
        #expect(rules.normalizedScore(voteAverage: 1) == 0)
        #expect(rules.normalizedScore(voteAverage: 3) == 50)
        #expect(rules.normalizedScore(voteAverage: 5) == 100)
        #expect(rules.normalizedScore(voteAverage: 5.5) == nil)
    }
}

@Suite struct FinalGradeTests {
    @Test func theVotesAloneSetTheGrade() throws {
        // A 4.0 average on the 1 to 5 scale is three quarters of the way up.
        let score = try #require(FinalGrade.score(voteAverage: 4))
        #expect(score == 75)
    }

    @Test func staysInsideZeroToOneHundred() throws {
        #expect(try #require(FinalGrade.score(voteAverage: 1)) == 0)
        #expect(try #require(FinalGrade.score(voteAverage: 5)) == 100)
    }

    @Test func rejectsAnAverageOffTheScale() {
        #expect(FinalGrade.score(voteAverage: 0.5) == nil)
        #expect(FinalGrade.score(voteAverage: 5.5) == nil)
    }

    @Test func followsTheScaleInTheRules() throws {
        let tenPoint = VotingRules(scale: 1...10, windowSeconds: 60, minimumVotes: 1)
        #expect(try #require(FinalGrade.score(voteAverage: 5.5, rules: tenPoint)) == 50)
    }
}

@Suite struct SlotUpgradeTests {
    @Test func aHigherScoreReplacesTheSlot() {
        #expect(SlotUpgrade.shouldReplace(currentScore: 70, newScore: 71))
        #expect(!SlotUpgrade.shouldReplace(currentScore: 70, newScore: 70))
        #expect(!SlotUpgrade.shouldReplace(currentScore: 70, newScore: 60))
    }

    @Test func aGradedShotReplacesAnUngradedOne() {
        #expect(SlotUpgrade.shouldReplace(currentScore: nil, newScore: 10))
        #expect(!SlotUpgrade.shouldReplace(currentScore: 10, newScore: nil))
        #expect(!SlotUpgrade.shouldReplace(currentScore: nil, newScore: nil))
    }

    private func shot(_ id: String, score: Double? = nil, reading: Double? = nil) -> SlotShot {
        SlotShot(
            photoID: id,
            aircraftType: "Boeing 737 MAX 8",
            airline: "",
            registration: "",
            score: score,
            technicalReading: reading,
            loggedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func aGradeAlwaysOutranksATechnicalReading() {
        let read = shot("read", reading: 95)
        let graded = shot("graded", score: 40, reading: 30)
        #expect(SlotUpgrade.shouldReplace(current: read, new: graded))
        #expect(!SlotUpgrade.shouldReplace(current: graded, new: read))
    }

    @Test func twoGradedShotsAreRankedByGradeAndNeverByReading() {
        let low = shot("low", score: 60, reading: 99)
        let high = shot("high", score: 61, reading: 10)
        #expect(SlotUpgrade.shouldReplace(current: low, new: high))
        #expect(!SlotUpgrade.shouldReplace(current: high, new: low))
    }

    @Test func twoShotsWithNoGradeAreRankedByReading() {
        let soft = shot("soft", reading: 55)
        let sharp = shot("sharp", reading: 80)
        #expect(SlotUpgrade.shouldReplace(current: soft, new: sharp))
        #expect(!SlotUpgrade.shouldReplace(current: sharp, new: soft))
        #expect(!SlotUpgrade.shouldReplace(current: soft, new: shot("same", reading: 55)))
        #expect(SlotUpgrade.shouldReplace(current: shot("unread"), new: soft))
        #expect(!SlotUpgrade.shouldReplace(current: soft, new: shot("unread")))
    }
}

@Suite struct OrderingTests {
    @Test func tiersAndRaritiesAreOrdered() {
        #expect(Tier.logged < Tier.bronze)
        #expect(Tier.silver < Tier.gold)
        #expect(Tier.allCases.max() == .gold)
        #expect(Rarity.common < Rarity.legendary)
    }
}
