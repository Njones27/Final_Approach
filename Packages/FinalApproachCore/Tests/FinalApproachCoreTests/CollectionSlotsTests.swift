import Foundation
import Testing

@testable import FinalApproachCore

@Suite struct CollectionBookTests {
    let thresholds = TierThresholds(bronze: 50, silver: 65, gold: 80)!

    private func shot(
        _ id: String,
        type: String = "Boeing 737 MAX 8",
        airline: String = "Alaska Airlines",
        registration: String = "N823AK",
        score: Double? = nil,
        day: Double
    ) -> SlotShot {
        SlotShot(
            photoID: id,
            aircraftType: type,
            airline: airline,
            registration: registration,
            score: score,
            loggedAt: Date(timeIntervalSince1970: day * 86_400)
        )
    }

    @Test func onePhotoFillsASlotInEveryViewItHasANameFor() {
        let shots = [shot("a", score: 83, day: 1)]
        let types = CollectionBook.entries(for: shots, kind: .aircraftType, thresholds: thresholds)
        let airlines = CollectionBook.entries(for: shots, kind: .airline, thresholds: thresholds)
        let registrations = CollectionBook.entries(for: shots, kind: .registration, thresholds: thresholds)
        #expect(types.map(\.title) == ["Boeing 737 MAX 8"])
        #expect(airlines.map(\.title) == ["Alaska Airlines"])
        #expect(registrations.map(\.title) == ["N823AK"])
        #expect(types.first?.bestPhotoID == "a")
        #expect(types.first?.tier == .gold)
    }

    @Test func aPhotoWithNoNameFillsNoSlotInThatView() {
        let shots = [shot("a", airline: "", registration: "  ", day: 1)]
        #expect(CollectionBook.entries(for: shots, kind: .aircraftType, thresholds: thresholds).count == 1)
        #expect(CollectionBook.entries(for: shots, kind: .airline, thresholds: thresholds).isEmpty)
        #expect(CollectionBook.entries(for: shots, kind: .registration, thresholds: thresholds).isEmpty)
    }

    @Test func noPhotoFillsALiverySlotYet() {
        let shots = [shot("a", score: 83, day: 1)]
        #expect(CollectionBook.entries(for: shots, kind: .livery, thresholds: thresholds).isEmpty)
    }

    /// The acceptance test for the collection requirement.
    @Test func aNewRegistrationOfACollectedTypeLeavesTheTypeSlotUnlessItGradesHigher() {
        let first = shot("first", registration: "N823AK", score: 83, day: 1)
        let lower = shot("lower", registration: "N915AK", score: 71, day: 2)

        var types = CollectionBook.entries(for: [first, lower], kind: .aircraftType, thresholds: thresholds)
        var registrations = CollectionBook.entries(for: [first, lower], kind: .registration, thresholds: thresholds)
        #expect(registrations.map(\.title) == ["N823AK", "N915AK"])
        #expect(types.count == 1)
        #expect(types.first?.bestPhotoID == "first")
        #expect(types.first?.upgradedAt == nil)
        #expect(types.first?.photoIDs == ["first", "lower"])

        let higher = shot("higher", registration: "N915AK", score: 90, day: 3)
        types = CollectionBook.entries(for: [first, lower, higher], kind: .aircraftType, thresholds: thresholds)
        registrations = CollectionBook.entries(for: [first, lower, higher], kind: .registration, thresholds: thresholds)
        #expect(types.first?.bestPhotoID == "higher")
        #expect(types.first?.upgradedAt == higher.loggedAt)
        #expect(types.first?.firstLoggedAt == first.loggedAt)
        #expect(types.first?.photoIDs == ["higher", "first", "lower"])
        #expect(registrations.first { $0.title == "N823AK" }?.bestPhotoID == "first")
        #expect(registrations.first { $0.title == "N915AK" }?.bestPhotoID == "higher")
    }

    @Test func anEqualGradeDoesNotTakeTheSlot() {
        let shots = [shot("first", score: 80, day: 1), shot("second", score: 80, day: 2)]
        let entry = CollectionBook.entries(for: shots, kind: .aircraftType, thresholds: thresholds).first
        #expect(entry?.bestPhotoID == "first")
    }

    @Test func aGradedPhotoBeatsAnUngradedOneAndNotTheOtherWayRound() {
        let ungradedFirst = [shot("plain", day: 1), shot("graded", score: 40, day: 2)]
        var entry = CollectionBook.entries(for: ungradedFirst, kind: .aircraftType, thresholds: thresholds).first
        #expect(entry?.bestPhotoID == "graded")
        #expect(entry?.tier == .logged)
        #expect(entry?.bestScore == 40)

        let gradedFirst = [shot("graded", score: 40, day: 1), shot("plain", day: 2)]
        entry = CollectionBook.entries(for: gradedFirst, kind: .aircraftType, thresholds: thresholds).first
        #expect(entry?.bestPhotoID == "graded")
    }

    @Test func anUngradedSlotKeepsItsFirstPhotoAndListsTheNewestNext() {
        let shots = [shot("one", day: 1), shot("two", day: 2), shot("three", day: 3)]
        let entry = CollectionBook.entries(for: shots, kind: .aircraftType, thresholds: thresholds).first
        #expect(entry?.bestPhotoID == "one")
        #expect(entry?.bestScore == nil)
        #expect(entry?.tier == .logged)
        #expect(entry?.photoIDs == ["one", "three", "two"])
    }

    @Test func slotsFollowTheOrderPhotosWereLoggedAndNotTheOrderGiven() {
        let shots = [
            shot("late", type: "Airbus A350-900", day: 5),
            shot("early", type: "Embraer E175", day: 1),
        ]
        let types = CollectionBook.entries(for: shots, kind: .aircraftType, thresholds: thresholds)
        #expect(types.map(\.title) == ["Embraer E175", "Airbus A350-900"])
    }

    @Test func namesThatDifferOnlyInCaseOrSpacingShareASlot() {
        let shots = [
            shot("a", type: "Boeing 737 MAX 8", registration: "G-ABCD", day: 1),
            shot("b", type: "  boeing  737 max 8 ", registration: "gabcd", day: 2),
        ]
        let types = CollectionBook.entries(for: shots, kind: .aircraftType, thresholds: thresholds)
        let registrations = CollectionBook.entries(for: shots, kind: .registration, thresholds: thresholds)
        #expect(types.count == 1)
        #expect(types.first?.title == "Boeing 737 MAX 8")
        #expect(registrations.count == 1)
        #expect(registrations.first?.title == "G-ABCD")
        #expect(registrations.first?.key == "gabcd")
    }

    @Test func aRemovedPhotoLeavesNoSlotBehind() {
        let first = shot("first", score: 83, day: 1)
        let other = shot("other", type: "Embraer E175", registration: "", score: 71, day: 2)
        let all = CollectionBook.entries(for: [first, other], kind: .aircraftType, thresholds: thresholds)
        let afterDelete = CollectionBook.entries(for: [other], kind: .aircraftType, thresholds: thresholds)
        #expect(all.count == 2)
        #expect(afterDelete.map(\.title) == ["Embraer E175"])
    }

    @Test func eachSlotHasItsOwnID() {
        let shots = [shot("a", score: 83, day: 1)]
        let type = CollectionBook.entries(for: shots, kind: .aircraftType, thresholds: thresholds).first
        let airline = CollectionBook.entries(for: shots, kind: .airline, thresholds: thresholds).first
        #expect(type?.id == "aircraftType:boeing 737 max 8")
        #expect(airline?.id == "airline:alaska airlines")
    }
}
