import Testing

@testable import FinalApproachCore

@Suite struct GeoPointTests {
    @Test func rejectsAPointOutsideTheGlobe() {
        #expect(GeoPoint(latitude: 91, longitude: 0) == nil)
        #expect(GeoPoint(latitude: 0, longitude: -181) == nil)
        #expect(GeoPoint(latitude: -90, longitude: 180) != nil)
    }

    @Test func aPointIsNoDistanceFromItself() throws {
        let point = try #require(GeoPoint(latitude: 33.6407, longitude: -84.4277))
        #expect(point.distance(to: point) == 0)
    }

    @Test func oneDegreeOfLatitudeIsAbout111Kilometers() throws {
        let south = try #require(GeoPoint(latitude: 33, longitude: -84))
        let north = try #require(GeoPoint(latitude: 34, longitude: -84))
        let distance = south.distance(to: north)
        #expect(abs(distance - 111_195) < 100)
        #expect(abs(north.distance(to: south) - distance) < 0.001)
    }

    @Test func atlantaToSeattleIsAbout3500Kilometers() throws {
        let atlanta = try #require(GeoPoint(latitude: 33.6407, longitude: -84.4277))
        let seattle = try #require(GeoPoint(latitude: 47.4502, longitude: -122.3088))
        let kilometers = atlanta.distance(to: seattle) / 1000
        #expect(kilometers > 3_480 && kilometers < 3_530)
    }
}

@Suite struct NearestLandmarkTests {
    private func landmark(_ id: String, _ latitude: Double, _ longitude: Double) throws -> Landmark {
        Landmark(id: id, point: try #require(GeoPoint(latitude: latitude, longitude: longitude)))
    }

    @Test func picksTheClosestLandmarkInRange() throws {
        let landmarks = [
            try landmark("south", 33.6215, -84.3990),
            try landmark("north", 33.6568, -84.4310),
        ]
        let photo = try #require(GeoPoint(latitude: 33.6220, longitude: -84.3995))
        let found = NearestLandmark.find(to: photo, among: landmarks, within: 1_000)
        #expect(found?.landmark.id == "south")
        #expect((found?.distance ?? .infinity) < 100)
    }

    @Test func findsNothingBeyondTheMaximumDistance() throws {
        let landmarks = [try landmark("south", 33.6215, -84.3990)]
        let farAway = try #require(GeoPoint(latitude: 47.4502, longitude: -122.3088))
        #expect(NearestLandmark.find(to: farAway, among: landmarks, within: 1_000) == nil)
        #expect(NearestLandmark.find(to: farAway, among: [], within: 1_000) == nil)
    }

    @Test func theFirstOfTwoEquallyCloseLandmarksWins() throws {
        let landmarks = [
            try landmark("first", 33.6215, -84.3990),
            try landmark("second", 33.6215, -84.3990),
        ]
        let photo = try #require(GeoPoint(latitude: 33.6215, longitude: -84.3990))
        #expect(NearestLandmark.find(to: photo, among: landmarks, within: 10)?.landmark.id == "first")
    }
}

@Suite struct GeoBoundsTests {
    @Test func hasNoBoundsWithoutPoints() {
        #expect(GeoBounds(points: []) == nil)
    }

    @Test func framesEveryPoint() throws {
        let points = [
            try #require(GeoPoint(latitude: 33.62, longitude: -84.46)),
            try #require(GeoPoint(latitude: 33.66, longitude: -84.40)),
            try #require(GeoPoint(latitude: 33.64, longitude: -84.43)),
        ]
        let bounds = try #require(GeoBounds(points: points))
        #expect(abs(bounds.center.latitude - 33.64) < 1e-9)
        #expect(abs(bounds.center.longitude - -84.43) < 1e-9)
        #expect(abs(bounds.latitudeSpan - 0.04) < 1e-9)
        #expect(abs(bounds.longitudeSpan - 0.06) < 1e-9)
    }

    @Test func paddingGrowsTheSpansAndASinglePointGetsTheMinimum() throws {
        let points = [
            try #require(GeoPoint(latitude: 33.62, longitude: -84.46)),
            try #require(GeoPoint(latitude: 33.66, longitude: -84.40)),
        ]
        let spans = try #require(GeoBounds(points: points)).framedSpans(padding: 0.5, minimumSpan: 0.01)
        #expect(abs(spans.latitude - 0.06) < 1e-9)
        #expect(abs(spans.longitude - 0.09) < 1e-9)

        let single = try #require(GeoBounds(points: [points[0]])).framedSpans(padding: 0.5, minimumSpan: 0.01)
        #expect(single.latitude == 0.01)
        #expect(single.longitude == 0.01)
    }
}
