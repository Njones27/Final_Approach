import Testing

@testable import FinalApproachCore

@Suite struct FrameRegionTests {
    @Test func keepsOnlyThePartInsideThePhoto() throws {
        let region = try #require(FrameRegion(x: -0.25, y: 0.5, width: 0.75, height: 1))
        #expect(region.x == 0)
        #expect(region.width == 0.5)
        #expect(region.y == 0.5)
        #expect(region.height == 0.5)
    }

    @Test func rejectsARegionOutsideThePhoto() {
        #expect(FrameRegion(x: 1.5, y: 0, width: 0.25, height: 0.25) == nil)
        #expect(FrameRegion(x: 0, y: 0, width: 0, height: 0.5) == nil)
        #expect(FrameRegion(x: .nan, y: 0, width: 0.5, height: 0.5) == nil)
    }

    @Test func areaIsTheShareOfThePhoto() throws {
        let region = try #require(FrameRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(region.area == 0.25)
        #expect(FrameRegion.whole.area == 1)
    }

    @Test func namesTheSidesARegionReaches() throws {
        let left = try #require(FrameRegion(x: 0, y: 0.25, width: 0.5, height: 0.5))
        #expect(left.edgesTouched(margin: 0.01) == [.left])
        let centered = try #require(FrameRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(centered.edgesTouched(margin: 0.01).isEmpty)
        #expect(FrameRegion.whole.edgesTouched(margin: 0.01) == [.left, .right, .top, .bottom])
    }
}

@Suite struct LuminanceGridTests {
    /// A grid whose columns hold the given brightness values.
    static func grid(columns: [UInt8], height: Int) -> LuminanceGrid {
        var pixels: [UInt8] = []
        for _ in 0..<height {
            pixels.append(contentsOf: columns)
        }
        return LuminanceGrid(width: columns.count, height: height, pixels: pixels)!
    }

    @Test func rejectsTheWrongNumberOfPixels() {
        #expect(LuminanceGrid(width: 2, height: 2, pixels: [0, 0, 0]) == nil)
        #expect(LuminanceGrid(width: 0, height: 2, pixels: []) == nil)
    }

    @Test func aFlatPhotoHasNoDetail() {
        let flat = Self.grid(columns: [120, 120, 120, 120, 120, 120], height: 6)
        #expect(flat.laplacianVariance() == 0)
    }

    @Test func aHardEdgeHoldsMoreDetailThanASmoothRamp() throws {
        let edge = Self.grid(columns: [0, 0, 0, 0, 255, 255, 255, 255], height: 8)
        let ramp = Self.grid(columns: [0, 30, 60, 90, 120, 150, 180, 210], height: 8)
        let edgeDetail = try #require(edge.laplacianVariance())
        let rampDetail = try #require(ramp.laplacianVariance())
        #expect(rampDetail == 0)
        #expect(edgeDetail > 1000)
    }

    @Test func detailIsMeasuredOnlyInsideTheRegion() throws {
        let edge = Self.grid(columns: [0, 0, 0, 0, 0, 0, 255, 255], height: 8)
        let leftHalf = try #require(FrameRegion(x: 0, y: 0, width: 0.5, height: 1))
        #expect(edge.laplacianVariance(in: leftHalf) == 0)
        #expect(try #require(edge.laplacianVariance()) > 0)
    }

    @Test func aRegionUnderThreePixelsCannotBeMeasured() {
        let small = Self.grid(columns: [0, 255], height: 2)
        #expect(small.laplacianVariance() == nil)
    }

    @Test func countsTheShareOfBrightAndDarkPixels() throws {
        let grid = try #require(LuminanceGrid(width: 4, height: 2, pixels: [255, 255, 255, 255, 0, 0, 0, 0]))
        #expect(grid.share(atOrAbove: 250) == 0.5)
        #expect(grid.share(atOrBelow: 5) == 0.5)
        let topHalf = try #require(FrameRegion(x: 0, y: 0, width: 1, height: 0.5))
        #expect(grid.share(atOrAbove: 250, in: topHalf) == 1)
        #expect(grid.share(atOrBelow: 5, in: topHalf) == 0)
    }
}

@Suite struct PhotoMeasurementsTests {
    @Test func measuresSharpnessAndExposureOverTheAircraft() throws {
        let grid = LuminanceGridTests.grid(columns: [0, 0, 0, 0, 255, 255, 255, 255], height: 8)
        let rightHalf = try #require(FrameRegion(x: 0.5, y: 0, width: 0.5, height: 1))
        let measurements = PhotoMeasurements(
            grid: grid,
            subject: rightHalf,
            tiltDegrees: 1.5,
            rules: TestRules.rules
        )
        #expect(measurements.subject == rightHalf)
        #expect(measurements.sharpness == 0)
        #expect(measurements.blownHighlights == 1)
        #expect(measurements.crushedShadows == 0)
        #expect(measurements.tiltDegrees == 1.5)
    }

    @Test func measuresTheWholePhotoWhenNoAircraftWasFound() throws {
        let grid = LuminanceGridTests.grid(columns: [0, 0, 0, 0, 255, 255, 255, 255], height: 8)
        let measurements = PhotoMeasurements(grid: grid, subject: nil, tiltDegrees: nil, rules: TestRules.rules)
        #expect(measurements.subject == nil)
        #expect(try #require(measurements.sharpness) > 0)
        #expect(measurements.blownHighlights == 0.5)
        #expect(measurements.crushedShadows == 0.5)
    }
}
