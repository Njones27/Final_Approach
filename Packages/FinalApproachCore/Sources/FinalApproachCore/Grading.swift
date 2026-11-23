/// How the final grade blends the AI aesthetic score with community votes.
///
/// The design starts at 30 percent AI and 70 percent votes. The AI share is
/// expected to grow as a model trained on vote data improves, so the weights
/// are data and not constants.
public struct GradeWeights: Equatable, Codable, Sendable {
    public let ai: Double
    public let votes: Double

    /// Returns nil unless both weights are non-negative and they sum to 1.
    public init?(ai: Double, votes: Double) {
        guard ai >= 0, votes >= 0, abs(ai + votes - 1) < 1e-9 else { return nil }
        self.ai = ai
        self.votes = votes
    }

    private init(uncheckedAI ai: Double, votes: Double) {
        self.ai = ai
        self.votes = votes
    }

    public static let launch = GradeWeights(uncheckedAI: 0.3, votes: 0.7)
}

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
    /// Blends an AI aesthetic score and a weighted vote average into a final
    /// score from 0 to 100.
    ///
    /// - Parameters:
    ///   - aiScore: The AI aesthetic score, from 0 to 100.
    ///   - voteAverage: The reputation-weighted vote average on the voting scale.
    /// - Returns: The final score, or nil when either input is out of range.
    public static func score(
        aiScore: Double,
        voteAverage: Double,
        weights: GradeWeights = .launch,
        rules: VotingRules = .launch
    ) -> Double? {
        guard (0...100).contains(aiScore),
              let voteScore = rules.normalizedScore(voteAverage: voteAverage)
        else { return nil }
        return weights.ai * aiScore + weights.votes * voteScore
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
}
