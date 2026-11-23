import Testing

@testable import FinalApproachCore

@Suite struct CameraSettingsTests {
    @Test func formatsEachSettingForDisplay() {
        let settings = CameraSettings(
            cameraMake: "Canon",
            cameraModel: "Canon EOS R5",
            lensModel: "RF100-500mm F4.5-7.1 L IS USM",
            focalLength: 400,
            aperture: 7.1,
            exposureTime: 1.0 / 640,
            iso: 200
        )
        #expect(settings.cameraName == "Canon EOS R5")
        #expect(settings.focalLengthText == "400 mm")
        #expect(settings.apertureText == "f/7.1")
        #expect(settings.shutterText == "1/640 s")
        #expect(settings.isoText == "ISO 200")
        #expect(!settings.isEmpty)
    }

    @Test func joinsTheMakeAndModelWhenTheModelDoesNotRepeatTheMake() {
        #expect(CameraSettings(cameraMake: "SONY", cameraModel: "ILCE-7M4").cameraName == "SONY ILCE-7M4")
        #expect(CameraSettings(cameraMake: "FUJIFILM", cameraModel: "X-T5").cameraName == "FUJIFILM X-T5")
        #expect(CameraSettings(cameraMake: "NIKON CORPORATION", cameraModel: "NIKON Z 8").cameraName == "NIKON Z 8")
        #expect(CameraSettings(cameraMake: "Apple").cameraName == "Apple")
        #expect(CameraSettings(cameraModel: "iPhone 17 Pro").cameraName == "iPhone 17 Pro")
        #expect(CameraSettings().cameraName == nil)
    }

    @Test func dropsTrailingZerosAndKeepsOneDecimal() {
        #expect(CameraSettings(aperture: 4).apertureText == "f/4")
        #expect(CameraSettings(aperture: 5.6).apertureText == "f/5.6")
        #expect(CameraSettings(focalLength: 23.96).focalLengthText == "24 mm")
        #expect(CameraSettings(focalLength: 6.86).focalLengthText == "6.9 mm")
    }

    @Test func showsLongExposuresInSecondsAndShortOnesAsFractions() {
        #expect(CameraSettings(exposureTime: 0.001).shutterText == "1/1000 s")
        #expect(CameraSettings(exposureTime: 0.5).shutterText == "1/2 s")
        #expect(CameraSettings(exposureTime: 1).shutterText == "1 s")
        #expect(CameraSettings(exposureTime: 2.5).shutterText == "2.5 s")
        #expect(CameraSettings(exposureTime: 30).shutterText == "30 s")
    }

    @Test func treatsEmptyAndImpossibleValuesAsMissing() {
        let settings = CameraSettings(
            cameraMake: "  ",
            cameraModel: "",
            lensModel: " ",
            focalLength: 0,
            aperture: -1,
            exposureTime: .infinity,
            iso: 0
        )
        #expect(settings.isEmpty)
        #expect(settings.cameraName == nil)
        #expect(settings.focalLengthText == nil)
        #expect(settings.apertureText == nil)
        #expect(settings.shutterText == nil)
        #expect(settings.isoText == nil)
    }

    @Test func trimsSpacesAroundNames() {
        let settings = CameraSettings(cameraModel: "  X-T5 ", lensModel: "XF150-600mm ")
        #expect(settings.cameraModel == "X-T5")
        #expect(settings.lensModel == "XF150-600mm")
    }
}

@Suite struct CaptureTimestampTests {
    @Test func readsAnExifDateAndTime() {
        let timestamp = CaptureTimestamp(exif: "2026:11:14 17:42:05")
        #expect(timestamp?.year == 2026)
        #expect(timestamp?.month == 11)
        #expect(timestamp?.day == 14)
        #expect(timestamp?.hour == 17)
        #expect(timestamp?.minute == 42)
        #expect(timestamp?.second == 5)
    }

    @Test func rejectsTextWithAnotherShape() {
        #expect(CaptureTimestamp(exif: "") == nil)
        #expect(CaptureTimestamp(exif: "2026-11-14 17:42:05") == nil)
        #expect(CaptureTimestamp(exif: "2026:11:14") == nil)
        #expect(CaptureTimestamp(exif: "2026:11:14 17:42") == nil)
        #expect(CaptureTimestamp(exif: "2026:11:14T17:42:05") == nil)
        #expect(CaptureTimestamp(exif: "0000:00:00 00:00:00") == nil)
    }

    @Test func rejectsFieldsThatAreOutOfRange() {
        #expect(CaptureTimestamp(exif: "2026:13:14 17:42:05") == nil)
        #expect(CaptureTimestamp(exif: "2026:11:32 17:42:05") == nil)
        #expect(CaptureTimestamp(exif: "2026:11:14 24:42:05") == nil)
        #expect(CaptureTimestamp(exif: "2026:11:14 17:60:05") == nil)
    }
}
