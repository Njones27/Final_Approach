import Foundation

/// Where one posted photo stands with the vote, as its owner is told.
///
/// Voting is blind, so the score is nil until the grade is final. Until
/// then the owner knows how many votes are in and nothing more.
public struct PostStanding: Equatable, Codable, Sendable {
    public let postedAt: Date
    /// When the voting window ends. A photo short of votes stays open past
    /// it, until the vote that brings it to the minimum.
    public let closesAt: Date
    public let voteCount: Int
    /// The final grade from 0 to 100, or nil while voting is open.
    public let finalScore: Int?

    /// A negative count is read as none, and a score is kept on the scale.
    public init(postedAt: Date, closesAt: Date, voteCount: Int, finalScore: Int? = nil) {
        self.postedAt = postedAt
        self.closesAt = closesAt
        self.voteCount = max(voteCount, 0)
        self.finalScore = finalScore.map { min(max($0, 0), 100) }
    }

    /// True once the votes have set the grade.
    public var isFinal: Bool { finalScore != nil }

    /// The whole hours left in the voting window, rounded up. It is 0 once
    /// the window has ended.
    public func hoursLeft(at now: Date) -> Int {
        let seconds = closesAt.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 3600).rounded(.up))
    }

    /// How many more votes the photo needs before its grade can be final.
    public func votesNeeded(minimumVotes: Int) -> Int {
        max(minimumVotes - voteCount, 0)
    }
}
