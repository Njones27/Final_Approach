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

    @Test func contrastIsTheVarianceOfTheBrightness() throws {
        let flat = Self.grid(columns: [90, 90, 90, 90], height: 4)
        #expect(flat.luminanceVariance() == 0)
        // Half black and half white is as far from its mean as it can be.
        let split = Self.grid(columns: [0, 0, 255, 255], height: 4)
        #expect(split.luminanceVariance() == 16256.25)
        let leftHalf = try #require(FrameRegion(x: 0, y: 0, width: 0.5, height: 1))
        #expect(split.luminanceVariance(in: leftHalf) == 0)
    }
}

@Suite struct SubjectMaskTests {
    /// A 4 by 4 mask that marks the middle four pixels.
    static let middle = SubjectMask(
        width: 4,
        height: 4,
        isSubject: [
            false, false, false, false,
            false, true, true, false,
            false, true, true, false,
            false, false, false, false,
        ]
    )!

    @Test func rejectsTheWrongNumberOfPixels() {
        #expect(SubjectMask(width: 2, height: 2, isSubject: [true]) == nil)
        #expect(SubjectMask(width: 0, height: 0, isSubject: []) == nil)
    }

    @Test func boundsTheMarkedPixels() throws {
        let region = try #require(Self.middle.boundingRegion)
        #expect(region == FrameRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    @Test func anEmptyMaskHasNoBounds() throws {
        let empty = try #require(SubjectMask(width: 2, height: 2, isSubject: [false, false, false, false]))
        #expect(empty.boundingRegion == nil)
    }

    @Test func aSmallMaskIsStretchedOverALargerGrid() {
        #expect(SubjectMask.positions(from: 8, to: 4) == [0, 0, 1, 1, 2, 2, 3, 3])
        #expect(SubjectMask.positions(from: 4, to: 4) == [0, 1, 2, 3])
        #expect(SubjectMask.positions(from: 2, to: 4) == [1, 3])
    }

    @Test func onlyTheMarkedPixelsAreMeasured() throws {
        // The left half is black and the right half is white. The mask marks
        // the middle, which is half black and half white.
        let grid = LuminanceGridTests.grid(columns: [0, 0, 0, 0, 255, 255, 255, 255], height: 8)
        #expect(grid.share(atOrAbove: 250, mask: Self.middle) == 0.5)
        #expect(grid.share(atOrBelow: 5, mask: Self.middle) == 0.5)
        #expect(try #require(grid.laplacianVariance(mask: Self.middle)) > 0)
        #expect(grid.luminanceVariance(mask: Self.middle) == 16256.25)
    }

    @Test func detailOutsideTheMaskIsIgnored() throws {
        // The only edge is in the last two columns, outside the mask.
        let grid = LuminanceGridTests.grid(columns: [0, 0, 0, 0, 0, 0, 0, 255], height: 8)
        #expect(grid.laplacianVariance(mask: Self.middle) == 0)
        #expect(try #require(grid.laplacianVariance()) > 0)
    }

    @Test func anEmptyMaskGivesNoReading() throws {
        let grid = LuminanceGridTests.grid(columns: [0, 0, 0, 0, 255, 255, 255, 255], height: 8)
        let empty = try #require(SubjectMask(width: 2, height: 2, isSubject: [false, false, false, false]))
        #expect(grid.laplacianVariance(mask: empty) == nil)
        #expect(grid.luminanceVariance(mask: empty) == nil)
        #expect(grid.share(atOrAbove: 250, mask: empty) == nil)
    }
}

@Suite struct PhotoMeasurementsTests {
    let grid = LuminanceGridTests.grid(columns: [0, 0, 0, 0, 255, 255, 255, 255], height: 8)

    @Test func measuresTheAircraftsOwnPixelsWhenThereIsAMask() throws {
        let measurements = PhotoMeasurements(
            grid: grid,
            mask: SubjectMaskTests.middle,
            fallbackBox: .whole,
            tiltDegrees: 1.5,
            rules: TestRules.rules
        )
        #expect(measurements.subject == FrameRegion(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(measurements.subjectSource == .mask)
        #expect(try #require(measurements.sharpness) > 0)
        #expect(measurements.contrast == 16256.25)
        #expect(measurements.blownHighlights == 0.5)
        #expect(measurements.crushedShadows == 0.5)
        #expect(measurements.tiltDegrees == 1.5)
    }

    @Test func measuresInsideTheBoxWhenThereIsNoMask() throws {
        let rightHalf = try #require(FrameRegion(x: 0.5, y: 0, width: 0.5, height: 1))
        let measurements = PhotoMeasurements(
            grid: grid,
            mask: nil,
            fallbackBox: rightHalf,
            tiltDegrees: nil,
            rules: TestRules.rules
        )
        #expect(measurements.subject == rightHalf)
        #expect(measurements.subjectSource == .box)
        #expect(measurements.sharpness == 0)
        #expect(measurements.contrast == 0)
        #expect(measurements.blownHighlights == 1)
        #expect(measurements.crushedShadows == 0)
    }

    @Test func anEmptyMaskFallsBackToTheBox() throws {
        let empty = try #require(SubjectMask(width: 2, height: 2, isSubject: [false, false, false, false]))
        let measurements = PhotoMeasurements(
            grid: grid,
            mask: empty,
            fallbackBox: .whole,
            tiltDegrees: nil,
            rules: TestRules.rules
        )
        #expect(measurements.subjectSource == .box)
    }

    @Test func aPhotoWithNoAircraftKeepsOnlyItsTilt() {
        // Readings over a whole photo say little about the aircraft, so
        // none are taken when it was not found.
        let measurements = PhotoMeasurements(
            grid: grid,
            mask: nil,
            fallbackBox: nil,
            tiltDegrees: 1.5,
            rules: TestRules.rules
        )
        #expect(measurements == PhotoMeasurements(tiltDegrees: 1.5))
    }

    @Test func aSourceWithoutAPlaceIsDropped() {
        #expect(PhotoMeasurements(subjectSource: .mask).subjectSource == nil)
    }
}
