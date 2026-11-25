import Testing

@testable import FinalApproachCore

@Suite struct PlaceGridTests {
    private let grid = PlaceGrid(cellsPerDegree: 1000)!

    private func point(_ latitude: Double, _ longitude: Double) throws -> GeoPoint {
        try #require(GeoPoint(latitude: latitude, longitude: longitude))
    }

    @Test func aGridNeedsAtLeastOneCell() {
        #expect(PlaceGrid(cellsPerDegree: 0) == nil)
        #expect(PlaceGrid(cellsPerDegree: -5) == nil)
        #expect(PlaceGrid(cellsPerDegree: 1) != nil)
    }

    @Test func namesACellTheWayTheBackendDoes() throws {
        let atlanta = try point(33.64037, -84.42761)
        let sydney = try point(-33.94612, 151.17722)
        let london = try point(51.4703, -0.4543)
        #expect(grid.placeID(at: atlanta) == "n33640w84428")
        #expect(grid.placeID(at: sydney) == "s33946e151177")
        #expect(grid.placeID(at: london) == "n51470w454")
    }

    @Test func everyPointInACellHasTheSameID() throws {
        let id = grid.placeID(at: try point(33.64, -84.428))
        let northEastCorner = try point(33.64049, -84.42751)
        let southWestCorner = try point(33.63951, -84.42849)
        let nextNorth = try point(33.64051, -84.428)
        let nextEast = try point(33.64, -84.42749)
        #expect(grid.placeID(at: northEastCorner) == id)
        #expect(grid.placeID(at: southWestCorner) == id)
        #expect(grid.placeID(at: nextNorth) != id)
        #expect(grid.placeID(at: nextEast) != id)
    }

    @Test func zeroHasOneIDOnEachAxis() throws {
        let justNorthWest = try point(0.0001, -0.0001)
        let justSouthEast = try point(-0.0001, 0.0001)
        #expect(grid.placeID(at: justNorthWest) == "n0e0")
        #expect(grid.placeID(at: justSouthEast) == "n0e0")
    }

    @Test func theTwoSidesOfTheDateLineAreOneCell() throws {
        let east = try point(0, 180)
        let west = try point(0, -180)
        #expect(grid.placeID(at: east) == grid.placeID(at: west))
    }

    @Test func theCenterOfACellIsWhatIsSentInPlaceOfThePoint() throws {
        let exact = try point(33.64037, -84.42761)
        let center = grid.cellCenter(of: exact)
        #expect(abs(center.latitude - 33.64) < 1e-9)
        #expect(abs(center.longitude - -84.428) < 1e-9)
        // The middle is in the same cell, so the backend files it there.
        #expect(grid.placeID(at: center) == grid.placeID(at: exact))
        // It is never more than a cell away from the point.
        #expect(exact.distance(to: center) < 120)
    }

    @Test func anIDReadsBackToTheMiddleOfItsCell() throws {
        let center = try #require(grid.center(ofPlaceID: "n33640w84428"))
        #expect(abs(center.latitude - 33.64) < 1e-9)
        #expect(abs(center.longitude - -84.428) < 1e-9)
        let south = try #require(grid.center(ofPlaceID: "s33946e151177"))
        #expect(abs(south.latitude - -33.946) < 1e-9)
        #expect(abs(south.longitude - 151.177) < 1e-9)
        #expect(grid.center(ofPlaceID: "n0e0") == GeoPoint(latitude: 0, longitude: 0))
    }

    @Test func theSizeOfACellIsSaidAsARoundNumber() {
        #expect(grid.roughCellMeters == 100)
        #expect(PlaceGrid(cellsPerDegree: 100)?.roughCellMeters == 1000)
        #expect(PlaceGrid(cellsPerDegree: 500)?.roughCellMeters == 200)
        #expect(PlaceGrid(cellsPerDegree: 1)?.roughCellMeters == 100_000)
        #expect(PlaceGrid(cellsPerDegree: 10_000_000)?.roughCellMeters == 1)
    }

    @Test func anIDThatNamesNoCellReadsBackToNothing() {
        let bad = [
            "", "n1", "e1n1", "N1E1", "n01e1", "n1e01", "s0e0", "n0w0", "n90001e0", "n0e180000",
            "n1.5e2", "n1e2 ", "n-1e2", "xyz-east-fence",
        ]
        for id in bad {
            #expect(grid.center(ofPlaceID: id) == nil, "\(id)")
        }
    }
}
