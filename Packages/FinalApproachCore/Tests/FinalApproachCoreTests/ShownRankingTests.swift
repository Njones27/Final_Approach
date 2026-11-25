import Testing

@testable import FinalApproachCore

@Suite struct ShownRankingTests {
    private func tally(_ id: String, _ photoCount: Int, _ bestScore: Int) -> ShownTally {
        ShownTally(id: id, photoCount: photoCount, bestScore: bestScore)
    }

    @Test func thePlaceWithTheMostPhotosComesFirst() {
        let ranked = ShownRanking.ranked([tally("few", 2, 95), tally("many", 9, 60), tally("some", 4, 80)])
        #expect(ranked.map(\.id) == ["many", "some", "few"])
    }

    @Test func theBetterTopPhotoBreaksATie() {
        let ranked = ShownRanking.ranked([tally("good", 3, 70), tally("best", 3, 91)])
        #expect(ranked.map(\.id) == ["best", "good"])
    }

    @Test func theOrderHoldsStillWhenEverythingIsEqual() {
        let forward = ShownRanking.ranked([tally("b", 3, 70), tally("a", 3, 70), tally("c", 3, 70)])
        let backward = ShownRanking.ranked([tally("c", 3, 70), tally("a", 3, 70), tally("b", 3, 70)])
        #expect(forward.map(\.id) == ["a", "b", "c"])
        #expect(backward == forward)
    }

    @Test func nothingShownRanksNothing() {
        #expect(ShownRanking.ranked([]).isEmpty)
    }
}
