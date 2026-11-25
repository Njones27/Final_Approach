import Foundation
import Testing

@testable import FinalApproachCore

@Suite struct SunPositionTests {
    private func point(_ latitude: Double, _ longitude: Double) throws -> GeoPoint {
        try #require(GeoPoint(latitude: latitude, longitude: longitude))
    }

    @Test func theSunIsDueSouthOfAtlantaAtItsNoon() throws {
        // 25 November 2026 at 17:25 UTC, which is 12:25 in Atlanta.
        let noon = Date(timeIntervalSince1970: 1_795_582_800 + 12 * 3600 + 25 * 60)
        let sun = SunPosition.at(try point(33.6407, -84.4277), on: noon)
        #expect(abs(sun.azimuth - 180) < 1)
        #expect(abs(sun.elevation - 35.5) < 0.5)
    }

    @Test func theSunIsHighOverTheEquatorAtTheJuneSolstice() throws {
        // 21 June 2026 at 12:00 UTC, seen from where the equator meets Greenwich.
        let sun = SunPosition.at(try point(0, 0), on: Date(timeIntervalSince1970: 1_782_043_200))
        #expect(abs(sun.elevation - 66.56) < 0.3)
        // It stands to the north, on either side of due north.
        #expect(Compass.difference(sun.azimuth, 0) < 5)
    }

    @Test func theSunIsBelowTheHorizonAtMidnight() throws {
        let midnight = Date(timeIntervalSince1970: 1_795_582_800)
        let sun = SunPosition.at(try point(33.6407, -84.4277), on: midnight)
        #expect(sun.elevation < -30)
    }
}

@Suite struct SunlightTests {
    private let rules = LightRules(
        horizonElevation: -0.833,
        goldenLowestElevation: -4,
        goldenHighestElevation: 6,
        behindWithinDegrees: 70,
        stepSeconds: 60
    )
    /// Midnight in Atlanta on 25 November 2026, which is 05:00 UTC.
    private let dayStart = Date(timeIntervalSince1970: 1_795_582_800)

    private func atlanta() throws -> GeoPoint {
        try #require(GeoPoint(latitude: 33.6407, longitude: -84.4277))
    }

    private func light(viewBearing: Double?) throws -> DayLight {
        Sunlight.light(
            at: try atlanta(),
            from: dayStart,
            to: dayStart.addingTimeInterval(86_400),
            viewBearing: viewBearing,
            rules: rules
        )
    }

    /// True when a moment is within a few minutes of a time of day in UTC.
    private func isNear(_ date: Date?, hour: Int, minute: Int) -> Bool {
        guard let date else { return false }
        // 05:00 UTC is the start of the day, so the offset counts from there.
        let expected = dayStart.addingTimeInterval(Double((hour - 5) * 3600 + minute * 60))
        return abs(date.timeIntervalSince(expected)) <= 240
    }

    @Test func findsSunriseAndSunsetInAtlanta() throws {
        let day = try light(viewBearing: nil)
        // 7:19 in the morning and 5:31 in the evening, Atlanta time.
        #expect(isNear(day.sunrise, hour: 12, minute: 19))
        #expect(isNear(day.sunset, hour: 22, minute: 31))
    }

    @Test func goldenHourComesTwiceADay() throws {
        let day = try light(viewBearing: nil)
        #expect(day.goldenHours.count == 2)
        let morning = try #require(day.goldenHours.first)
        let evening = try #require(day.goldenHours.last)
        #expect(isNear(morning.start, hour: 12, minute: 3))
        #expect(isNear(morning.end, hour: 12, minute: 56))
        #expect(isNear(evening.start, hour: 21, minute: 54))
        #expect(isNear(evening.end, hour: 22, minute: 48))
    }

    @Test func aPlaceThatDoesNotSayWhichWayItLooksHasNoSunBehind() throws {
        let day = try light(viewBearing: nil)
        #expect(day.sunBehind.isEmpty)
    }

    @Test func lookingNorthInNovemberKeepsTheSunBehindAllDay() throws {
        let day = try light(viewBearing: 0)
        #expect(day.sunBehind.count == 1)
        let window = try #require(day.sunBehind.first)
        #expect(window.start == day.sunrise)
        #expect(window.end == day.sunset)
    }

    @Test func lookingSouthInNovemberNeverHasTheSunBehind() throws {
        let day = try light(viewBearing: 180)
        #expect(day.sunBehind.isEmpty)
    }

    @Test func lookingWestHasTheSunBehindInTheMorningOnly() throws {
        let day = try light(viewBearing: 270)
        #expect(day.sunBehind.count == 1)
        let window = try #require(day.sunBehind.first)
        #expect(window.start == day.sunrise)
        // It ends at about 11:14 in the morning, Atlanta time.
        #expect(isNear(window.end, hour: 16, minute: 14))
    }

    @Test func lookingEastHasTheSunBehindInTheAfternoonOnly() throws {
        let day = try light(viewBearing: 90)
        #expect(day.sunBehind.count == 1)
        let window = try #require(day.sunBehind.first)
        // It starts at about 1:37 in the afternoon, Atlanta time.
        #expect(isNear(window.start, hour: 18, minute: 37))
        #expect(window.end == day.sunset)
    }

    @Test func whereTheSunDoesNotSetThereIsNoSunriseOrSunset() throws {
        // Tromso on 21 June 2026, from 00:00 UTC.
        let tromso = try #require(GeoPoint(latitude: 69.65, longitude: 18.96))
        let start = Date(timeIntervalSince1970: 1_782_000_000)
        let day = Sunlight.light(
            at: tromso,
            from: start,
            to: start.addingTimeInterval(86_400),
            viewBearing: nil,
            rules: rules
        )
        #expect(day.sunrise == nil)
        #expect(day.sunset == nil)
    }

    @Test func aStretchWithNoLengthOrNoStepHasNoLight() throws {
        let empty = DayLight(sunrise: nil, sunset: nil, goldenHours: [], sunBehind: [])
        let nothing = Sunlight.light(at: try atlanta(), from: dayStart, to: dayStart, viewBearing: 0, rules: rules)
        #expect(nothing == empty)
        let still = LightRules(
            horizonElevation: -0.833,
            goldenLowestElevation: -4,
            goldenHighestElevation: 6,
            behindWithinDegrees: 70,
            stepSeconds: 0
        )
        let stuck = Sunlight.light(
            at: try atlanta(),
            from: dayStart,
            to: dayStart.addingTimeInterval(86_400),
            viewBearing: 0,
            rules: still
        )
        #expect(stuck == empty)
    }
}
