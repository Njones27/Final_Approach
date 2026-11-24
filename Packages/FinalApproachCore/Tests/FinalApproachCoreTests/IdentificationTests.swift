import Testing

@testable import FinalApproachCore

private func point(_ latitude: Double, _ longitude: Double) throws -> GeoPoint {
    try #require(GeoPoint(latitude: latitude, longitude: longitude))
}

private func rules(
    maximumDistance: Double = 10_000,
    maximumAltitude: Double = 10_000,
    distanceWeight: Double = 1,
    altitudeWeight: Double = 1,
    bearingWeight: Double = 1,
    limit: Int = 3
) throws -> FlightRankingRules {
    try #require(
        FlightRankingRules(
            maximumDistance: maximumDistance,
            maximumAltitude: maximumAltitude,
            distanceWeight: distanceWeight,
            altitudeWeight: altitudeWeight,
            bearingWeight: bearingWeight,
            limit: limit
        )
    )
}

private func sighting(
    _ id: String,
    _ latitude: Double,
    _ longitude: Double,
    altitude: Double = 1_000,
    registration: String? = nil
) throws -> FlightSighting {
    FlightSighting(
        id: id,
        callsign: id.uppercased(),
        position: try point(latitude, longitude),
        altitude: altitude,
        registration: registration
    )
}

@Suite struct CompassTests {
    @Test func bearingsFollowTheCompass() throws {
        let start = try point(33.64, -84.43)
        #expect(abs(start.bearing(to: try point(33.74, -84.43)) - 0) < 0.01)
        #expect(abs(start.bearing(to: try point(33.64, -84.33)) - 90) < 0.1)
        #expect(abs(start.bearing(to: try point(33.54, -84.43)) - 180) < 0.01)
        #expect(abs(start.bearing(to: try point(33.64, -84.53)) - 270) < 0.1)
    }

    @Test func aDirectionIsBroughtIntoOneTurn() {
        #expect(Compass.normalized(370) == 10)
        #expect(Compass.normalized(-10) == 350)
        #expect(Compass.normalized(360) == 0)
        #expect(Compass.normalized(0) == 0)
    }

    @Test func theDifferenceIsTheSmallestTurn() {
        #expect(Compass.difference(350, 10) == 20)
        #expect(Compass.difference(10, 350) == 20)
        #expect(Compass.difference(0, 180) == 180)
        #expect(Compass.difference(90, 90) == 0)
        #expect(Compass.difference(-90, 270) == 0)
    }
}

@Suite struct FlightRankingRulesTests {
    @Test func rejectsValuesThatCannotRank() {
        #expect(FlightRankingRules(maximumDistance: 0, maximumAltitude: 1, distanceWeight: 1, altitudeWeight: 1, bearingWeight: 1, limit: 3) == nil)
        #expect(FlightRankingRules(maximumDistance: 1, maximumAltitude: 0, distanceWeight: 1, altitudeWeight: 1, bearingWeight: 1, limit: 3) == nil)
        #expect(FlightRankingRules(maximumDistance: 1, maximumAltitude: 1, distanceWeight: 1, altitudeWeight: 1, bearingWeight: 1, limit: 0) == nil)
        #expect(FlightRankingRules(maximumDistance: 1, maximumAltitude: 1, distanceWeight: -1, altitudeWeight: 1, bearingWeight: 1, limit: 3) == nil)
        #expect(FlightRankingRules(maximumDistance: 1, maximumAltitude: 1, distanceWeight: 0, altitudeWeight: 0, bearingWeight: 1, limit: 3) == nil)
        #expect(FlightRankingRules(maximumDistance: 1, maximumAltitude: 1, distanceWeight: 1, altitudeWeight: 0, bearingWeight: 0, limit: 1) != nil)
    }
}

@Suite struct FlightRankerTests {
    @Test func theCloserAircraftRanksFirst() throws {
        let observer = try point(33.64, -84.43)
        let near = try sighting("near", 33.645, -84.43)
        let far = try sighting("far", 33.70, -84.43)
        let ranked = FlightRanker.rank([far, near], seenFrom: observer, facing: nil, rules: try rules())
        #expect(ranked.map(\.id) == ["near", "far"])
        #expect(ranked[0].score > ranked[1].score)
        #expect(ranked[0].distance < ranked[1].distance)
    }

    @Test func theLowerAircraftRanksFirstAtTheSameDistance() throws {
        let observer = try point(33.64, -84.43)
        let low = try sighting("low", 33.65, -84.43, altitude: 500)
        let high = try sighting("high", 33.65, -84.43, altitude: 8_000)
        let ranked = FlightRanker.rank([high, low], seenFrom: observer, facing: nil, rules: try rules())
        #expect(ranked.map(\.id) == ["low", "high"])
    }

    @Test func leavesOutAircraftTooFarOrTooHigh() throws {
        let observer = try point(33.64, -84.43)
        let cruising = try sighting("cruising", 33.65, -84.43, altitude: 35_000)
        let distant = try sighting("distant", 34.64, -84.43)
        let close = try sighting("close", 33.65, -84.43)
        let ranked = FlightRanker.rank([cruising, distant, close], seenFrom: observer, facing: nil, rules: try rules())
        #expect(ranked.map(\.id) == ["close"])
    }

    @Test func theCameraHeadingBreaksATieOfDistance() throws {
        let observer = try point(33.64, -84.43)
        let north = try sighting("north", 33.66, -84.43)
        let south = try sighting("south", 33.62, -84.43)
        let facingSouth = FlightRanker.rank([north, south], seenFrom: observer, facing: 180, rules: try rules())
        #expect(facingSouth.map(\.id) == ["south", "north"])
        let facingNorth = FlightRanker.rank([north, south], seenFrom: observer, facing: 0, rules: try rules())
        #expect(facingNorth.map(\.id) == ["north", "south"])
    }

    @Test func aHeadingCountsForNothingWhenItsWeightIsZero() throws {
        let observer = try point(33.64, -84.43)
        let north = try sighting("north", 33.65, -84.43)
        let south = try sighting("south", 33.60, -84.43)
        let noBearing = try rules(bearingWeight: 0)
        let ranked = FlightRanker.rank([south, north], seenFrom: observer, facing: 180, rules: noBearing)
        #expect(ranked.map(\.id) == ["north", "south"])
    }

    @Test func keepsOnlyTheLimit() throws {
        let observer = try point(33.64, -84.43)
        let sightings = try (1...5).map { try sighting("f\($0)", 33.64 + Double($0) * 0.005, -84.43) }
        let ranked = FlightRanker.rank(sightings, seenFrom: observer, facing: nil, rules: try rules(limit: 2))
        #expect(ranked.map(\.id) == ["f1", "f2"])
    }

    @Test func scoresStayBetweenZeroAndOne() throws {
        let observer = try point(33.64, -84.43)
        let overhead = try sighting("overhead", 33.64, -84.43, altitude: -50)
        let edge = try sighting("edge", 33.72, -84.43, altitude: 9_900)
        let ranked = FlightRanker.rank([overhead, edge], seenFrom: observer, facing: 90, rules: try rules())
        #expect(ranked.count == 2)
        for flight in ranked {
            #expect(flight.score >= 0 && flight.score <= 1)
        }
    }

    @Test func noSightingsGiveNoFlights() throws {
        let observer = try point(33.64, -84.43)
        #expect(FlightRanker.rank([], seenFrom: observer, facing: nil, rules: try rules()).isEmpty)
    }
}

@Suite struct FlightSightingTests {
    @Test func describesTheFlightAndItsRoute() throws {
        let position = try point(33.64, -84.43)
        let full = FlightSighting(
            id: "a", callsign: "ASA331", position: position, altitude: 600,
            flightNumber: "AS331", origin: "SEA", destination: "ATL"
        )
        #expect(full.activity == "flight AS331 from SEA to ATL")
        let light = FlightSighting(id: "b", callsign: "DAL1482", position: position, altitude: 600)
        #expect(light.activity == "flight DAL1482")
        let arriving = FlightSighting(
            id: "c", callsign: "DAL1", position: position, altitude: 600, destination: "ATL"
        )
        #expect(arriving.activity == "flight DAL1 to ATL")
        let leaving = FlightSighting(
            id: "d", callsign: "DAL2", position: position, altitude: 600, origin: "ATL"
        )
        #expect(leaving.activity == "flight DAL2 from ATL")
    }
}

@Suite struct AircraftIdentifierTests {
    private func ranked(_ id: String, registration: String?, score: Double) throws -> RankedFlight {
        RankedFlight(
            sighting: try sighting(id, 33.64, -84.43, registration: registration),
            distance: 1_000,
            score: score
        )
    }

    private func reading(_ registration: String, confidence: Double = 0.9) -> RegistrationReading {
        RegistrationReading(registration: registration, country: "Test", confidence: confidence)
    }

    @Test func aReadingThatMatchesAFlightConfirmsIt() throws {
        let flights = [
            try ranked("first", registration: nil, score: 0.9),
            try ranked("second", registration: "N823AK", score: 0.5),
        ]
        let result = AircraftIdentifier.identify(
            readings: [reading("N823AK")],
            flights: flights,
            blockList: .empty
        )
        #expect(result.confirmedFlight?.id == "second")
        // The confirmed flight leads the list.
        #expect(result.flights.map(\.id) == ["second", "first"])
    }

    @Test func aMatchIgnoresCaseAndHyphens() throws {
        let flights = [try ranked("only", registration: "GABCD", score: 0.5)]
        let result = AircraftIdentifier.identify(
            readings: [reading("G-ABCD")],
            flights: flights,
            blockList: .empty
        )
        #expect(result.confirmedFlight?.id == "only")
    }

    @Test func aReadingWithNoMatchingFlightConfirmsNothing() throws {
        let flights = [try ranked("other", registration: "N1AB", score: 0.9)]
        let result = AircraftIdentifier.identify(
            readings: [reading("N823AK")],
            flights: flights,
            blockList: .empty
        )
        #expect(result.confirmedFlight == nil)
        #expect(result.readings.map(\.registration) == ["N823AK"])
        #expect(result.flights.map(\.id) == ["other"])
    }

    @Test func theSurestMatchingReadingWins() throws {
        let flights = [
            try ranked("a", registration: "N1AB", score: 0.9),
            try ranked("b", registration: "N2CD", score: 0.8),
        ]
        let result = AircraftIdentifier.identify(
            readings: [reading("N9ZZ"), reading("N2CD"), reading("N1AB")],
            flights: flights,
            blockList: .empty
        )
        #expect(result.confirmedFlight?.id == "b")
    }

    @Test func aBlockedRegistrationIsNeverSuggested() throws {
        let flights = [
            try ranked("blocked", registration: "N123AB", score: 0.9),
            try ranked("open", registration: nil, score: 0.5),
        ]
        let result = AircraftIdentifier.identify(
            readings: [reading("N123AB"), reading("N823AK")],
            flights: flights,
            blockList: RegistrationBlockList(registrations: ["n123ab"])
        )
        #expect(result.readings.map(\.registration) == ["N823AK"])
        #expect(result.flights.map(\.id) == ["open"])
        #expect(result.confirmedFlight == nil)
    }

    @Test func nothingReadAndNothingFlyingIsEmpty() {
        let result = AircraftIdentifier.identify(readings: [], flights: [], blockList: .empty)
        #expect(result.isEmpty)
        #expect(result == .none)
    }
}
