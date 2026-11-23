import Foundation

/// One aircraft the flight data provider saw near a place at one minute.
///
/// The provider's light answer has only the position and the callsign. Its
/// full answer adds the rest, so every other detail is optional.
public struct FlightSighting: Equatable, Sendable, Identifiable {
    /// The provider's id for the aircraft, such as its ICAO hex code.
    public let id: String
    public let callsign: String
    public let position: GeoPoint
    /// The altitude in feet.
    public let altitude: Double
    public let registration: String?
    public let aircraftType: String?
    public let airline: String?
    public let flightNumber: String?
    /// Where the flight came from, such as an airport code.
    public let origin: String?
    public let destination: String?

    public init(
        id: String,
        callsign: String,
        position: GeoPoint,
        altitude: Double,
        registration: String? = nil,
        aircraftType: String? = nil,
        airline: String? = nil,
        flightNumber: String? = nil,
        origin: String? = nil,
        destination: String? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.position = position
        self.altitude = altitude
        self.registration = registration
        self.aircraftType = aircraftType
        self.airline = airline
        self.flightNumber = flightNumber
        self.origin = origin
        self.destination = destination
    }

    /// The flight and its route as a short phrase, such as "flight AS331
    /// from SEA to ATL". The callsign stands in for a missing flight
    /// number.
    public var activity: String {
        let flight = "flight \(flightNumber ?? callsign)"
        switch (origin, destination) {
        case let (.some(origin), .some(destination)):
            return "\(flight) from \(origin) to \(destination)"
        case let (.some(origin), .none):
            return "\(flight) from \(origin)"
        case let (.none, .some(destination)):
            return "\(flight) to \(destination)"
        case (.none, .none):
            return flight
        }
    }
}

/// How the aircraft near a photo are ranked. The values are data, so the
/// ranking can be tuned without a release.
public struct FlightRankingRules: Equatable, Sendable, Codable {
    /// Aircraft farther away than this, in meters, are left out.
    public let maximumDistance: Double
    /// Aircraft higher than this, in feet, are left out.
    public let maximumAltitude: Double
    /// How much being close counts.
    public let distanceWeight: Double
    /// How much being low counts.
    public let altitudeWeight: Double
    /// How much sitting where the camera pointed counts. It only applies
    /// when the photo saved a compass heading.
    public let bearingWeight: Double
    /// How many aircraft to suggest.
    public let limit: Int

    /// Returns nil when a distance or the limit is not positive, a weight
    /// is negative, or the two weights that always apply are both zero.
    public init?(
        maximumDistance: Double,
        maximumAltitude: Double,
        distanceWeight: Double,
        altitudeWeight: Double,
        bearingWeight: Double,
        limit: Int
    ) {
        guard maximumDistance > 0, maximumAltitude > 0, limit > 0 else { return nil }
        guard distanceWeight >= 0, altitudeWeight >= 0, bearingWeight >= 0 else { return nil }
        guard distanceWeight + altitudeWeight > 0 else { return nil }
        self.maximumDistance = maximumDistance
        self.maximumAltitude = maximumAltitude
        self.distanceWeight = distanceWeight
        self.altitudeWeight = altitudeWeight
        self.bearingWeight = bearingWeight
        self.limit = limit
    }
}

/// An aircraft that may be the one in the photo, with how well it fits.
public struct RankedFlight: Equatable, Sendable, Identifiable {
    public let sighting: FlightSighting
    /// How far the aircraft was from where the photo was taken, in meters.
    public let distance: Double
    /// How well it fits, from 0 to 1.
    public let score: Double

    public var id: String { sighting.id }

    public init(sighting: FlightSighting, distance: Double, score: Double) {
        self.sighting = sighting
        self.distance = distance
        self.score = score
    }
}

/// Ranks the aircraft that were near a photo when it was taken.
public enum FlightRanker {
    /// The aircraft most likely to be in the photo, best first.
    ///
    /// An aircraft scores higher the closer and the lower it was. When the
    /// photo saved the direction the camera pointed, an aircraft in that
    /// direction scores higher too.
    ///
    /// - Parameters:
    ///   - observer: Where the photo was taken.
    ///   - heading: The compass direction the camera pointed, in degrees,
    ///     when the photo saved one.
    public static func rank(
        _ sightings: [FlightSighting],
        seenFrom observer: GeoPoint,
        facing heading: Double?,
        rules: FlightRankingRules
    ) -> [RankedFlight] {
        var ranked: [RankedFlight] = []
        for sighting in sightings {
            let distance = observer.distance(to: sighting.position)
            guard distance <= rules.maximumDistance, sighting.altitude <= rules.maximumAltitude else {
                continue
            }
            let closeness = 1 - distance / rules.maximumDistance
            let lowness = 1 - max(0, sighting.altitude) / rules.maximumAltitude
            var total = closeness * rules.distanceWeight + lowness * rules.altitudeWeight
            var weight = rules.distanceWeight + rules.altitudeWeight
            if let heading {
                let turn = Compass.difference(heading, observer.bearing(to: sighting.position))
                total += (1 - turn / 180) * rules.bearingWeight
                weight += rules.bearingWeight
            }
            ranked.append(RankedFlight(sighting: sighting, distance: distance, score: total / weight))
        }
        let sorted = ranked.sorted { first, second in
            if first.score != second.score {
                return first.score > second.score
            }
            return first.distance < second.distance
        }
        return Array(sorted.prefix(rules.limit))
    }
}

/// What the app worked out about the aircraft in a photo. The user confirms
/// or corrects it.
public struct Identification: Equatable, Sendable {
    /// The registrations read off the photo, surest first. A blocked
    /// registration is never listed.
    public let readings: [RegistrationReading]
    /// The aircraft that were flying there, best fit first. An aircraft
    /// with a blocked registration is never listed.
    public let flights: [RankedFlight]
    /// The flight whose registration was also read off the photo. Two
    /// sources agree on it, so it is taken as the aircraft in the photo.
    public let confirmedFlight: RankedFlight?

    public static let none = Identification(readings: [], flights: [], confirmedFlight: nil)

    public init(readings: [RegistrationReading], flights: [RankedFlight], confirmedFlight: RankedFlight?) {
        self.readings = readings
        self.flights = flights
        self.confirmedFlight = confirmedFlight
    }

    /// True when there is nothing to suggest.
    public var isEmpty: Bool {
        readings.isEmpty && flights.isEmpty
    }
}

/// Puts the registration reading and the flight data together.
public enum AircraftIdentifier {
    /// Works out the identification from what was read and what was flying.
    ///
    /// Blocked registrations are removed first, so nothing built on the
    /// result can show one. A confirmed flight moves to the front of the
    /// list.
    public static func identify(
        readings: [RegistrationReading],
        flights: [RankedFlight],
        blockList: RegistrationBlockList
    ) -> Identification {
        let openReadings = readings.filter { !blockList.contains($0.registration) }
        let openFlights = flights.filter { flight in
            guard let registration = flight.sighting.registration else { return true }
            return !blockList.contains(registration)
        }
        var confirmed: RankedFlight?
        for reading in openReadings {
            let key = CollectionBook.key(for: reading.registration, kind: .registration)
            let match = openFlights.first { flight in
                guard let registration = flight.sighting.registration else { return false }
                return CollectionBook.key(for: registration, kind: .registration) == key
            }
            if let match {
                confirmed = match
                break
            }
        }
        var ordered = openFlights
        if let confirmed, let index = ordered.firstIndex(of: confirmed) {
            ordered.remove(at: index)
            ordered.insert(confirmed, at: 0)
        }
        return Identification(readings: openReadings, flights: ordered, confirmedFlight: confirmed)
    }
}
