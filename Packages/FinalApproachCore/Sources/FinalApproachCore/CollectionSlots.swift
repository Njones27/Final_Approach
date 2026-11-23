import Foundation

/// What one logged photo offers the collection.
///
/// A name that is unknown, or that must stay hidden, is an empty string. A
/// photo fills no slot in a view it has no name for.
public struct SlotShot: Equatable, Sendable {
    public let photoID: String
    public let aircraftType: String
    public let airline: String
    public let registration: String
    /// The photo's final grade, or nil until it has one.
    public let score: Double?
    public let loggedAt: Date

    public init(
        photoID: String,
        aircraftType: String,
        airline: String,
        registration: String,
        score: Double?,
        loggedAt: Date
    ) {
        self.photoID = photoID
        self.aircraftType = aircraftType
        self.airline = airline
        self.registration = registration
        self.score = score
        self.loggedAt = loggedAt
    }

    /// The name this photo carries in one collection view. Liveries have no
    /// source yet, so no photo fills a livery slot.
    public func name(for kind: SlotKind) -> String {
        switch kind {
        case .aircraftType: aircraftType
        case .airline: airline
        case .registration: registration
        case .livery: ""
        }
    }
}

/// One slot in the collection, such as the Boeing 737 MAX 8 slot in the
/// types view. It keeps the user's best shot and every other shot of the
/// same thing.
public struct CollectionEntry: Equatable, Identifiable, Sendable {
    public let kind: SlotKind
    /// The slot's name with case and spacing removed, so "N823AK" and
    /// "n823ak" are one slot.
    public let key: String
    /// The name as the user first wrote it.
    public let title: String
    public let bestPhotoID: String
    /// The best photo's final grade, or nil when no photo here is graded.
    public let bestScore: Double?
    public let tier: Tier
    /// Every photo in the slot, best first.
    public let photoIDs: [String]
    public let firstLoggedAt: Date
    /// When a later photo took over as the best one, or nil when the first
    /// photo still holds the slot. It is the time that photo was logged.
    public let upgradedAt: Date?

    public var id: String { "\(kind.rawValue):\(key)" }
}

/// Sorts logged photos into collection slots.
///
/// The slots are worked out from the photos each time, so a deleted photo
/// leaves no stale slot behind.
public enum CollectionBook {
    /// The key two names share when they mean the same slot. Case and extra
    /// spaces are ignored. A registration also ignores punctuation, so
    /// "G-ABCD" and "GABCD" are one aircraft.
    public static func key(for name: String, kind: SlotKind) -> String {
        let folded = name.lowercased()
        if kind == .registration {
            return String(folded.filter { $0.isLetter || $0.isNumber })
        }
        return folded
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The slots of one collection view, in the order they were first
    /// filled.
    ///
    /// A later photo takes a slot only when it grades strictly higher, and
    /// any graded photo beats an ungraded one.
    public static func entries(
        for shots: [SlotShot],
        kind: SlotKind,
        thresholds: TierThresholds
    ) -> [CollectionEntry] {
        // Shots are taken in the order they were logged. Sorting by offset
        // as well keeps two shots logged at the same moment in input order.
        let ordered = shots.enumerated()
            .sorted { ($0.element.loggedAt, $0.offset) < ($1.element.loggedAt, $1.offset) }
            .map(\.element)

        var order: [String] = []
        var slots: [String: Slot] = [:]
        for shot in ordered {
            let name = shot.name(for: kind)
            let slotKey = key(for: name, kind: kind)
            guard !slotKey.isEmpty else { continue }
            if var slot = slots[slotKey] {
                if SlotUpgrade.shouldReplace(currentScore: slot.best.score, newScore: shot.score) {
                    slot.best = shot
                    slot.upgradedAt = shot.loggedAt
                }
                slot.shots.append(shot)
                slots[slotKey] = slot
            } else {
                order.append(slotKey)
                slots[slotKey] = Slot(
                    title: trimmed(name),
                    best: shot,
                    shots: [shot],
                    firstLoggedAt: shot.loggedAt,
                    upgradedAt: nil
                )
            }
        }

        return order.compactMap { slotKey in
            guard let slot = slots[slotKey] else { return nil }
            return CollectionEntry(
                kind: kind,
                key: slotKey,
                title: slot.title,
                bestPhotoID: slot.best.photoID,
                bestScore: slot.best.score,
                tier: slot.best.score.map { thresholds.tier(forScore: $0) } ?? .logged,
                photoIDs: bestFirst(slot.shots, best: slot.best).map(\.photoID),
                firstLoggedAt: slot.firstLoggedAt,
                upgradedAt: slot.upgradedAt
            )
        }
    }

    /// A slot while it is being filled.
    private struct Slot {
        let title: String
        var best: SlotShot
        var shots: [SlotShot]
        let firstLoggedAt: Date
        var upgradedAt: Date?
    }

    /// The slot's best photo, then the graded ones from the highest grade
    /// down, then the ungraded ones from the newest back.
    private static func bestFirst(_ shots: [SlotShot], best: SlotShot) -> [SlotShot] {
        let rest = shots
            .filter { $0.photoID != best.photoID }
            .sorted { first, second in
                switch (first.score, second.score) {
                case let (.some(a), .some(b)) where a != b: a > b
                case (.some, nil): true
                case (nil, .some): false
                default: first.loggedAt > second.loggedAt
                }
            }
        return [best] + rest
    }

    private static func trimmed(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
