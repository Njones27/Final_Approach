import Foundation
import Testing

@testable import FinalApproachCore

struct PostStandingTests {
    private let posted = Date(timeIntervalSince1970: 1_800_000_000)

    private func standing(votes: Int = 0, score: Int? = nil) -> PostStanding {
        PostStanding(
            postedAt: posted,
            closesAt: posted.addingTimeInterval(72 * 3600),
            voteCount: votes,
            finalScore: score
        )
    }

    @Test func theHoursLeftAreRoundedUp() {
        #expect(standing().hoursLeft(at: posted) == 72)
        #expect(standing().hoursLeft(at: posted.addingTimeInterval(60)) == 72)
        #expect(standing().hoursLeft(at: posted.addingTimeInterval(71 * 3600 + 1)) == 1)
    }

    @Test func noHoursAreLeftOnceTheWindowHasEnded() {
        #expect(standing().hoursLeft(at: posted.addingTimeInterval(72 * 3600)) == 0)
        #expect(standing().hoursLeft(at: posted.addingTimeInterval(100 * 3600)) == 0)
    }

    @Test func theVotesNeededNeverGoBelowNone() {
        #expect(standing(votes: 0).votesNeeded(minimumVotes: 5) == 5)
        #expect(standing(votes: 3).votesNeeded(minimumVotes: 5) == 2)
        #expect(standing(votes: 9).votesNeeded(minimumVotes: 5) == 0)
    }

    @Test func aStandingIsFinalOnlyWithAScore() {
        #expect(!standing(votes: 9).isFinal)
        #expect(standing(votes: 9, score: 81).isFinal)
    }

    @Test func aCountOrScoreOffTheScaleIsBroughtBack() {
        #expect(standing(votes: -2).voteCount == 0)
        #expect(standing(score: 140).finalScore == 100)
        #expect(standing(score: -3).finalScore == 0)
    }

    @Test func aStandingSurvivesBeingSaved() throws {
        let saved = try JSONEncoder().encode(standing(votes: 6, score: 74))
        #expect(try JSONDecoder().decode(PostStanding.self, from: saved) == standing(votes: 6, score: 74))
    }
}
