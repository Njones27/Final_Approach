/// The lowest final score that earns each graded tier.
///
/// The values are a product decision that has not been made yet, so they are
/// data that the app passes in and not constants in this package.
public struct TierThresholds: Equatable, Codable, Sendable {
    public let bronze: Double
    public let silver: Double
    public let gold: Double

    /// Returns nil unless the thresholds rise in order and sit between 0 and
    /// 100.
    public init?(bronze: Double, silver: Double, gold: Double) {
        guard bronze > 0, bronze < silver, silver < gold, gold <= 100 else { return nil }
        self.bronze = bronze
        self.silver = silver
        self.gold = gold
    }

    /// The tier a final score earns. A score under the bronze threshold stays
    /// at `logged`.
    public func tier(forScore score: Double) -> Tier {
        if score >= gold { return .gold }
        if score >= silver { return .silver }
        if score >= bronze { return .bronze }
        return .logged
    }

    /// The lowest score in a tier. `logged` starts at 0.
    public func lowerBound(of tier: Tier) -> Double {
        switch tier {
        case .logged: 0
        case .bronze: bronze
        case .silver: silver
        case .gold: gold
        }
    }

    /// The next tier above a score and the points still needed to reach it,
    /// or nil when the score is already gold.
    public func nextTier(aboveScore score: Double) -> (tier: Tier, pointsNeeded: Double)? {
        let current = tier(forScore: score)
        guard let next = Tier(rawValue: current.rawValue + 1) else { return nil }
        return (next, lowerBound(of: next) - score)
    }
}
