import Testing

@testable import FinalApproachCore

@Suite struct GradeWeightsTests {
    @Test func launchWeightsAreThirtySeventy() {
        #expect(GradeWeights.launch.ai == 0.3)
        #expect(GradeWeights.launch.votes == 0.7)
    }

    @Test func rejectsWeightsThatDoNotSumToOne() {
        #expect(GradeWeights(ai: 0.5, votes: 0.6) == nil)
        #expect(GradeWeights(ai: -0.1, votes: 1.1) == nil)
        #expect(GradeWeights(ai: 0.4, votes: 0.6) != nil)
    }
}

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
    @Test func blendsAIAndVotesWithLaunchWeights() throws {
        // 0.3 * 80 + 0.7 * 75 (a 4.0 average on the 1 to 5 scale)
        let score = try #require(FinalGrade.score(aiScore: 80, voteAverage: 4))
        #expect(abs(score - 76.5) < 1e-9)
    }

    @Test func staysInsideZeroToOneHundred() throws {
        let low = try #require(FinalGrade.score(aiScore: 0, voteAverage: 1))
        let high = try #require(FinalGrade.score(aiScore: 100, voteAverage: 5))
        #expect(low == 0)
        #expect(abs(high - 100) < 1e-9)
    }

    @Test func rejectsOutOfRangeInputs() {
        #expect(FinalGrade.score(aiScore: 101, voteAverage: 3) == nil)
        #expect(FinalGrade.score(aiScore: 50, voteAverage: 0.5) == nil)
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
}

@Suite struct OrderingTests {
    @Test func tiersAndRaritiesAreOrdered() {
        #expect(Tier.logged < Tier.bronze)
        #expect(Tier.silver < Tier.gold)
        #expect(Tier.allCases.max() == .gold)
        #expect(Rarity.common < Rarity.legendary)
    }
}
