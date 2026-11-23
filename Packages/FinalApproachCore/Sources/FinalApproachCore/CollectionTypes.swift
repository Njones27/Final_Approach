/// The grade level of a collection slot's best photo.
///
/// A photo that was logged but never graded sits at `logged`. The score
/// thresholds for the graded tiers are a product decision that has not been
/// made yet, so this type only defines the order.
public enum Tier: Int, CaseIterable, Comparable, Codable, Sendable {
    case logged
    case bronze
    case silver
    case gold

    public static func < (lhs: Tier, rhs: Tier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .logged: "Logged"
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        }
    }
}

/// How hard a slot is to fill.
public enum Rarity: Int, CaseIterable, Comparable, Codable, Sendable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    public static func < (lhs: Rarity, rhs: Rarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        }
    }
}

/// The collection views a single photo can fill a slot in.
public enum SlotKind: String, CaseIterable, Codable, Sendable {
    case aircraftType
    case airline
    case registration
    case livery
}
