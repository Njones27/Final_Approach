/// How much is shown at one spot or place, which is what a ranked list
/// orders them by.
public struct ShownTally: Equatable, Sendable {
    public let id: String
    /// How many graded photos are shown there.
    public let photoCount: Int
    /// The grade of the best photo there, from 0 to 100.
    public let bestScore: Int

    public init(id: String, photoCount: Int, bestScore: Int) {
        self.id = id
        self.photoCount = photoCount
        self.bestScore = bestScore
    }
}

public enum ShownRanking {
    /// The tallies in the order a ranked list shows them.
    ///
    /// The place with the most photos comes first. Two with the same count
    /// are ordered by their best photo's grade, and then by id, so the list
    /// holds still from one load to the next.
    public static func ranked(_ tallies: [ShownTally]) -> [ShownTally] {
        tallies.sorted { first, second in
            if first.photoCount != second.photoCount {
                return first.photoCount > second.photoCount
            }
            if first.bestScore != second.bestScore {
                return first.bestScore > second.bestScore
            }
            return first.id < second.id
        }
    }
}
