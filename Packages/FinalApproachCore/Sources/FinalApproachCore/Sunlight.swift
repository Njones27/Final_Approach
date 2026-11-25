import Foundation

/// Where the sun is in the sky, seen from a point on the ground.
public struct SunPosition: Equatable, Sendable {
    /// The compass direction of the sun, in degrees from 0 up to 360, where
    /// 0 is north and 90 is east.
    public let azimuth: Double
    /// How far the sun is above the horizon, in degrees. It is negative
    /// while the sun is below it.
    public let elevation: Double

    public init(azimuth: Double, elevation: Double) {
        self.azimuth = azimuth
        self.elevation = elevation
    }

    /// The sun's place in the sky at a point and a moment.
    ///
    /// This is the short method from the Astronomical Almanac. It is good
    /// to about a hundredth of a degree for the years 1950 to 2050, which
    /// places a sunrise within a minute. It leaves out the bending of light
    /// near the horizon, which `LightRules.horizonElevation` allows for.
    public static func at(_ point: GeoPoint, on date: Date) -> SunPosition {
        let radians = Double.pi / 180
        // Days since noon on 1 January 2000, the almanac's starting point.
        let days = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0

        let meanLongitude = wrapped(280.460 + 0.985_647_4 * days, 360)
        let meanAnomaly = wrapped(357.528 + 0.985_600_3 * days, 360) * radians
        let eclipticLongitude = (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly)) * radians
        let tilt = (23.439 - 0.000_000_4 * days) * radians

        let rightAscension = atan2(cos(tilt) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(tilt) * sin(eclipticLongitude))

        // The turn of the Earth, in hours, and from it how far the sun is
        // past the point's own meridian.
        let siderealHours = wrapped(18.697_374_558 + 24.065_709_824_419_08 * days, 24)
        let hourAngle = (siderealHours * 15 + point.longitude) * radians - rightAscension
        let latitude = point.latitude * radians

        let height = sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle)
        let elevation = asin(min(1, max(-1, height))) / radians
        let azimuth = atan2(
            -sin(hourAngle),
            tan(declination) * cos(latitude) - sin(latitude) * cos(hourAngle)
        ) / radians
        return SunPosition(azimuth: Compass.normalized(azimuth), elevation: elevation)
    }

    /// Brings a number into the range from 0 up to `size`.
    private static func wrapped(_ value: Double, _ size: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: size)
        return remainder < 0 ? remainder + size : remainder
    }
}

/// What counts as good light. These are data, so they can be tuned without
/// a release.
public struct LightRules: Equatable, Sendable {
    /// The elevation at which the sun's upper edge meets the horizon, which
    /// is a little below zero because the air bends its light.
    public let horizonElevation: Double
    /// Golden hour runs while the sun is between these two elevations.
    public let goldenLowestElevation: Double
    public let goldenHighestElevation: Double
    /// The sun counts as behind a photographer while it is within this many
    /// degrees of the direction at their back.
    public let behindWithinDegrees: Double
    /// How far apart the moments are at which the sky is looked at. A window
    /// starts and ends on one of them.
    public let stepSeconds: Double

    public init(
        horizonElevation: Double,
        goldenLowestElevation: Double,
        goldenHighestElevation: Double,
        behindWithinDegrees: Double,
        stepSeconds: Double
    ) {
        self.horizonElevation = horizonElevation
        self.goldenLowestElevation = goldenLowestElevation
        self.goldenHighestElevation = goldenHighestElevation
        self.behindWithinDegrees = behindWithinDegrees
        self.stepSeconds = stepSeconds
    }
}

/// A stretch of time with a start and an end.
public struct TimeWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// The light at one place over a stretch of time, usually one day.
public struct DayLight: Equatable, Sendable {
    /// The first time the sun comes up, or nil when it does not.
    public let sunrise: Date?
    /// The first time the sun goes down, or nil when it does not.
    public let sunset: Date?
    /// When the sun is low enough for golden hour, in order.
    public let goldenHours: [TimeWindow]
    /// When the sun is up and behind a photographer who faces the way the
    /// place looks. It is empty for a place that does not say which way it
    /// looks.
    public let sunBehind: [TimeWindow]

    public init(sunrise: Date?, sunset: Date?, goldenHours: [TimeWindow], sunBehind: [TimeWindow]) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.goldenHours = goldenHours
        self.sunBehind = sunBehind
    }
}

public enum Sunlight {
    /// The most moments one call looks at, so a long stretch or a tiny step
    /// cannot hold the app up.
    static let maximumSteps = 20_000

    /// The light at a point from `start` to `end`.
    ///
    /// - Parameter viewBearing: The compass direction a photographer faces
    ///   to see the aircraft, or nil when the place does not say.
    public static func light(
        at point: GeoPoint,
        from start: Date,
        to end: Date,
        viewBearing: Double?,
        rules: LightRules
    ) -> DayLight {
        guard end > start, rules.stepSeconds > 0 else {
            return DayLight(sunrise: nil, sunset: nil, goldenHours: [], sunBehind: [])
        }
        let length = end.timeIntervalSince(start)
        let steps = min(Int((length / rules.stepSeconds).rounded(.down)), maximumSteps)
        let back = viewBearing.map { $0 + 180 }

        var sunrise: Date?
        var sunset: Date?
        var wasUp: Bool?
        var golden = WindowBuilder()
        var behind = WindowBuilder()

        for step in 0...steps {
            let moment = start.addingTimeInterval(Double(step) * rules.stepSeconds)
            let sun = SunPosition.at(point, on: moment)
            let isUp = sun.elevation > rules.horizonElevation
            if let wasUp {
                if isUp, !wasUp, sunrise == nil { sunrise = moment }
                if !isUp, wasUp, sunset == nil { sunset = moment }
            }
            wasUp = isUp

            let isGolden = sun.elevation >= rules.goldenLowestElevation
                && sun.elevation <= rules.goldenHighestElevation
            golden.add(isGolden, at: moment)

            let isBehind = back.map { isUp && Compass.difference(sun.azimuth, $0) <= rules.behindWithinDegrees }
            behind.add(isBehind ?? false, at: moment)
        }
        return DayLight(
            sunrise: sunrise,
            sunset: sunset,
            goldenHours: golden.finished(at: end),
            sunBehind: behind.finished(at: end)
        )
    }
}

/// Gathers the stretches of time during which something holds, from a row
/// of moments in order.
private struct WindowBuilder {
    private var windows: [TimeWindow] = []
    private var openedAt: Date?

    init() {}

    mutating func add(_ holds: Bool, at moment: Date) {
        if holds {
            if openedAt == nil { openedAt = moment }
        } else if let start = openedAt {
            windows.append(TimeWindow(start: start, end: moment))
            openedAt = nil
        }
    }

    /// The windows, with one still open closed at the end of the stretch.
    func finished(at end: Date) -> [TimeWindow] {
        guard let start = openedAt else { return windows }
        return windows + [TimeWindow(start: start, end: end)]
    }
}
