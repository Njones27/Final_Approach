import Foundation
import Testing

@testable import FinalApproachCore

@Suite struct ShownCameraTests {
    private let limits = ShownCameraLimits.launch

    @Test func theFourNumbersAreShownAndTheGearIsNot() throws {
        let settings = CameraSettings(
            cameraMake: "Canon",
            cameraModel: "Canon EOS R5",
            lensModel: "RF100-500mm F4.5-7.1 L IS USM",
            focalLength: 400,
            aperture: 7.1,
            exposureTime: 1.0 / 640,
            iso: 200
        )

        let shown = try #require(ShownCamera(showing: settings, within: limits))

        #expect(shown == ShownCamera(focalLength: 400, aperture: 7.1, exposureTime: 1.0 / 640, iso: 200))
        // What is sent names no camera and no lens.
        let data = try JSONEncoder().encode(shown)
        let sent = String(decoding: data, as: UTF8.self)
        #expect(!sent.contains("Canon"))
        #expect(!sent.contains("RF100"))
    }

    @Test func aPhotoWithNoNumbersShowsNoSettings() {
        #expect(ShownCamera(showing: CameraSettings(), within: limits) == nil)
        #expect(ShownCamera(showing: CameraSettings(cameraModel: "iPhone 17 Pro"), within: limits) == nil)
    }

    @Test func aPartTheBackendWouldRefuseIsLeftOutAndTheRestIsShown() {
        let odd = CameraSettings(focalLength: 9000, aperture: 0.2, exposureTime: 7200, iso: 400)
        #expect(ShownCamera(showing: odd, within: limits) == ShownCamera(iso: 400))

        let allOdd = CameraSettings(focalLength: 0.5, aperture: 500, exposureTime: 1e-9, iso: 50_000_000)
        #expect(ShownCamera(showing: allOdd, within: limits) == nil)
    }

    @Test func theEdgesOfTheLimitsAreInside() {
        let least = CameraSettings(focalLength: 1, aperture: 0.5, exposureTime: 1.0 / 1_000_000, iso: 1)
        let most = CameraSettings(focalLength: 5000, aperture: 128, exposureTime: 3600, iso: 10_000_000)
        #expect(ShownCamera(showing: least, within: limits)
            == ShownCamera(focalLength: 1, aperture: 0.5, exposureTime: 1.0 / 1_000_000, iso: 1))
        #expect(ShownCamera(showing: most, within: limits)
            == ShownCamera(focalLength: 5000, aperture: 128, exposureTime: 3600, iso: 10_000_000))
    }

    @Test func aPartThatIsNotSetIsNotSent() throws {
        let sent = try JSONEncoder().encode(ShownCamera(focalLength: 400, iso: 200))
        let object = try JSONSerialization.jsonObject(with: sent) as? [String: Any]
        #expect(object?.keys.sorted() == ["focalLength", "iso"])
    }

    @Test func whatIsSentReadsBackTheSame() throws {
        let shown = ShownCamera(focalLength: 560, aperture: 5.6, exposureTime: 1.0 / 3, iso: 12_800)
        let sent = try JSONEncoder().encode(shown)
        let read = try JSONDecoder().decode(ShownCamera.self, from: sent)
        #expect(read == shown)
    }

    @Test func anOddPartInAnAnswerIsReadAsNothing() throws {
        let answer = Data(#"{"focalLength":"long","aperture":5.6,"iso":200.5}"#.utf8)
        let read = try JSONDecoder().decode(ShownCamera.self, from: answer)
        #expect(read == ShownCamera(aperture: 5.6))

        let empty = try JSONDecoder().decode(ShownCamera.self, from: Data("{}".utf8))
        #expect(empty.isEmpty)
    }

    @Test func theNumbersKeepTheWordingUsedToShowThem() {
        let settings = ShownCamera(focalLength: 400, aperture: 5.6, exposureTime: 0.001, iso: 200).settings
        #expect(settings.focalLengthText == "400 mm")
        #expect(settings.apertureText == "f/5.6")
        #expect(settings.shutterText == "1/1000 s")
        #expect(settings.isoText == "ISO 200")
        #expect(settings.cameraName == nil)
    }
}
