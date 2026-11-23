import FinalApproachCore
import Testing
import UIKit

@testable import FinalApproach

@MainActor
struct PhotoAnalyzerTests {
    /// Draws an image whose top half is white and whose bottom half is black.
    private func splitImage(width: Int, height: Int) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        }
        return image.cgImage
    }

    @Test func theGridReadsRowsFromTheTopOfTheImage() throws {
        let image = try #require(splitImage(width: 40, height: 20))
        let grid = try #require(PhotoAnalyzer.luminanceGrid(from: image, maxPixelSize: 1600))
        #expect(grid.width == 40)
        #expect(grid.height == 20)

        let topHalf = try #require(FrameRegion(x: 0, y: 0, width: 1, height: 0.5))
        let bottomHalf = try #require(FrameRegion(x: 0, y: 0.5, width: 1, height: 0.5))
        #expect(grid.share(atOrAbove: 250, in: topHalf) == 1)
        #expect(grid.share(atOrBelow: 5, in: bottomHalf) == 1)
    }

    @Test func theGridIsScaledDownToTheAnalysisSize() throws {
        let image = try #require(splitImage(width: 400, height: 200))
        let grid = try #require(PhotoAnalyzer.luminanceGrid(from: image, maxPixelSize: 100))
        #expect(grid.width == 100)
        #expect(grid.height == 50)
    }

    @Test func aSmallImageIsNotScaledUp() throws {
        let image = try #require(splitImage(width: 40, height: 20))
        let grid = try #require(PhotoAnalyzer.luminanceGrid(from: image, maxPixelSize: 1600))
        #expect(grid.pixels.count == 800)
    }

    @Test func measuringAnImageReadsItsDetailAndExposure() throws {
        let image = try #require(splitImage(width: 400, height: 200))
        let measurements = PhotoAnalyzer.measure(image, rules: SampleData.checkRules)
        // Where Vision puts the subject is not fixed, so only the readings
        // that always exist are checked.
        #expect(measurements.sharpness != nil)
        #expect(measurements.blownHighlights != nil)
        #expect(measurements.crushedShadows != nil)
    }

    @Test func anImageWithNoPixelsGivesNoMeasurements() async {
        let measurements = await PhotoAnalyzer.measurements(for: UIImage(), rules: SampleData.checkRules)
        #expect(measurements == .none)
    }
}
