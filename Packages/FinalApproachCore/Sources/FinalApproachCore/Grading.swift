/// The rules for a community voting round.
public struct VotingRules: Equatable, Codable, Sendable {
    /// The lowest and highest vote a voter can cast.
    public let scale: ClosedRange<Int>
    /// How long a photo stays in the voting queue, in seconds.
    public let windowSeconds: Double
    /// The fewest votes a photo needs before its grade can finalize.
    public let minimumVotes: Int

    public init(scale: ClosedRange<Int>, windowSeconds: Double, minimumVotes: Int) {
        self.scale = scale
        self.windowSeconds = windowSeconds
        self.minimumVotes = minimumVotes
    }

    /// A 1 to 5 scale, a 72 hour window, and a 5 vote minimum.
    public static let launch = VotingRules(scale: 1...5, windowSeconds: 72 * 60 * 60, minimumVotes: 5)

    public func isValid(vote: Int) -> Bool {
        scale.contains(vote)
    }

    /// A grade finalizes once the window has closed and enough votes are in.
    public func canFinalize(voteCount: Int, secondsSinceOpened: Double) -> Bool {
        voteCount >= minimumVotes && secondsSinceOpened >= windowSeconds
    }

    /// Maps a weighted vote average on the voting scale onto 0 to 100.
    /// Returns nil when the average falls outside the scale.
    public func normalizedScore(voteAverage: Double) -> Double? {
        let low = Double(scale.lowerBound)
        let high = Double(scale.upperBound)
        guard high > low, voteAverage >= low, voteAverage <= high else { return nil }
        return (voteAverage - low) / (high - low) * 100
    }
}

public enum FinalGrade {
    /// The final score from 0 to 100, which the votes alone set.
    ///
    /// The technical check takes no part in it. The check is advice to the
    /// photographer, so a photo that breaks the rules on purpose is never
    /// marked down for it.
    ///
    /// - Parameter voteAverage: The reputation-weighted vote average on the
    ///   voting scale.
    /// - Returns: The final score, or nil when the average is off the scale.
    public static func score(voteAverage: Double, rules: VotingRules = .launch) -> Double? {
        rules.normalizedScore(voteAverage: voteAverage)
    }
}

public enum SlotUpgrade {
    /// A slot keeps the user's best shot. A new photo replaces it only when
    /// it scores strictly higher, and any graded photo beats an ungraded one.
    public static func shouldReplace(currentScore: Double?, newScore: Double?) -> Bool {
        switch (currentScore, newScore) {
        case (_, nil): false
        case (nil, .some): true
        case let (.some(current), .some(new)): new > current
        }
    }

    /// Whether a new shot takes a slot from the shot that holds it.
    ///
    /// A final grade always outranks a technical reading, because the
    /// reading is a private stand-in until the votes are in. Two shots with
    /// no grade are ranked by their readings, so the collection works for
    /// photos nobody has voted on yet.
    public static func shouldReplace(current: SlotShot, new: SlotShot) -> Bool {
        if current.score != nil || new.score != nil {
            return shouldReplace(currentScore: current.score, newScore: new.score)
        }
        return shouldReplace(currentScore: current.technicalReading, newScore: new.technicalReading)
    }
}
