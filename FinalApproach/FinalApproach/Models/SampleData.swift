import FinalApproachCore
import Foundation
import UIKit

/// Sample data for previews and for running the app before a backend exists.
///
/// The photos are the owner's own, from their portfolio site, with the
/// camera settings they were taken at. The grades, findings, votes, spots,
/// and map locations attached to them are invented, and the tier thresholds
/// and passing score are placeholders until the product decides the real
/// values.
enum SampleData {
    /// Placeholder tier thresholds.
    static let thresholds = TierThresholds(bronze: 50, silver: 65, gold: 80)!
    /// Placeholder passing score for one technical check.
    static let passingCheckScore = 75.0
    /// Placeholder score a check is expected to reach once it is fixed.
    static let fixTargetScore = 90.0
    /// Provisional rules for the technical check.
    ///
    /// The curves come from 40 finished aircraft photos measured on a Mac.
    /// That set holds no rejects, so the low end of each curve is a guess,
    /// and the photos were edited web exports and not camera originals.
    ///
    /// The horizon check is off. On those photos Vision reported a tilt only
    /// on aircraft against open sky, where it followed the wings, and never
    /// on a photo with a real ground line.
    static let checkRules = CheckRules(
        enabledChecks: [.sharpness, .exposure, .framing],
        analysisPixelSize: 1600,
        sharpnessOnMask: ScoreCurve(pairs: [(30, 10), (90, 45), (170, 75), (400, 90), (900, 100)])!,
        sharpnessInBox: ScoreCurve(pairs: [(15, 10), (35, 40), (55, 75), (150, 90), (400, 100)])!,
        sharpnessToContrast: ScoreCurve(pairs: [(0.03, 10), (0.15, 75), (0.4, 100)])!,
        fastShutterTime: 1.0 / 1000,
        tilt: ScoreCurve(pairs: [(0, 100), (0.5, 90), (1, 75), (2, 55), (5, 20), (10, 0)])!,
        maximumTilt: 10,
        highlightLevel: 252,
        shadowLevel: 3,
        highlights: ScoreCurve(pairs: [(0, 100), (0.01, 90), (0.04, 75), (0.1, 50), (0.3, 10), (0.6, 0)])!,
        shadows: ScoreCurve(pairs: [(0, 100), (0.05, 90), (0.35, 75), (0.5, 50), (0.8, 10)])!,
        subjectSize: ScoreCurve(pairs: [(0.01, 10), (0.03, 50), (0.07, 75), (0.2, 90), (0.4, 100)])!,
        edgeMargin: 0.01,
        closeUpArea: 0.6,
        cutOffScore: 40
    )

    /// Placeholder distance, in meters, within which a photo counts as
    /// taken from a spot.
    static let spotMatchRadius = 1_500.0
    /// How strongly a logged photo's saved copy is compressed.
    static let storedImageQuality = 0.9

    /// How a few countries write their registrations. The list is a
    /// starting set and grows from the backend later.
    static let registrationFormats: [RegistrationFormat] = [
        RegistrationFormat(country: "United States", prefix: "N", hasHyphen: false, suffix: .unitedStates),
        RegistrationFormat(country: "Canada", prefix: "C", hasHyphen: true, suffix: .letters(4...4)),
        RegistrationFormat(country: "Mexico", prefix: "XA", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "United Kingdom", prefix: "G", hasHyphen: true, suffix: .letters(4...4)),
        RegistrationFormat(country: "Ireland", prefix: "EI", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "Germany", prefix: "D", hasHyphen: true, suffix: .letters(4...4)),
        RegistrationFormat(country: "France", prefix: "F", hasHyphen: true, suffix: .letters(4...4)),
        RegistrationFormat(country: "Netherlands", prefix: "PH", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "Spain", prefix: "EC", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "Italy", prefix: "I", hasHyphen: true, suffix: .letters(4...4)),
        RegistrationFormat(country: "Switzerland", prefix: "HB", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "Turkey", prefix: "TC", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "United Arab Emirates", prefix: "A6", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "Qatar", prefix: "A7", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "Australia", prefix: "VH", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "New Zealand", prefix: "ZK", hasHyphen: true, suffix: .letters(3...3)),
        RegistrationFormat(country: "Japan", prefix: "JA", hasHyphen: false, suffix: .lettersAndNumbers(4...4)),
        RegistrationFormat(country: "South Korea", prefix: "HL", hasHyphen: false, suffix: .lettersAndNumbers(4...4)),
    ]

    /// Placeholder values for ranking the aircraft near a photo. They are
    /// tuned once real flight data arrives.
    static let flightRankingRules = FlightRankingRules(
        maximumDistance: 15_000,
        maximumAltitude: 12_000,
        distanceWeight: 0.5,
        altitudeWeight: 0.3,
        bearingWeight: 0.2,
        limit: 3
    )!

    /// Aircraft for previews and tests of the Add screen. Only the first
    /// carries full details, as the provider's light answer has a callsign
    /// and a position and nothing else. The flight number and route are
    /// invented.
    static let flights: [FlightSighting] = [
        FlightSighting(
            id: "sample-asa",
            callsign: "ASA331",
            position: Coordinate(latitude: 33.6262, longitude: -84.3921)!,
            altitude: 600,
            registration: "N823AK",
            aircraftType: "Boeing 737 MAX 8",
            airline: "Alaska Airlines",
            flightNumber: "AS331",
            origin: "SEA",
            destination: "ATL"
        ),
        FlightSighting(
            id: "sample-dal",
            callsign: "DAL1482",
            position: Coordinate(latitude: 33.6318, longitude: -84.3402)!,
            altitude: 2_400
        ),
        FlightSighting(
            id: "sample-skw",
            callsign: "SKW3765",
            position: Coordinate(latitude: 33.6871, longitude: -84.4410)!,
            altitude: 5_200
        ),
        // Too high to be in a photo taken from the ground nearby.
        FlightSighting(
            id: "sample-cruise",
            callsign: "UAL88",
            position: Coordinate(latitude: 33.6300, longitude: -84.4100)!,
            altitude: 36_000
        ),
    ]

    /// The app's state on sample data. Pass a store to keep logged photos
    /// on the device. Previews and tests leave it out and stay in memory.
    ///
    /// Pass flight data only for a preview or a test. The app itself has
    /// none until the backend exists.
    static func model(
        store: (any PhotoStore)? = nil,
        flightData: (any FlightDataProvider)? = nil,
        blockList: RegistrationBlockList = .empty
    ) -> CollectionModel {
        CollectionModel(
            photos: photos,
            profile: profile,
            voteQueue: voteQueue,
            airports: airports,
            thresholds: thresholds,
            passingCheckScore: passingCheckScore,
            checkRules: checkRules,
            fixTargetScore: fixTargetScore,
            spotMatchRadius: spotMatchRadius,
            storedImageQuality: storedImageQuality,
            registrationFormats: registrationFormats,
            flightRankingRules: flightRankingRules,
            blockList: blockList,
            flightData: flightData,
            store: store
        )
    }

    static let profile = Profile(
        name: "Sam Rivera",
        memberSince: "November 2026",
        votesCast: 42,
        level: 7,
        experience: 1240,
        experienceForNextLevel: 1500,
        voteWeight: 1.4
    )

    // MARK: Photos

    private static let vc25Findings = findings(horizon: 92, sharpness: 88, exposure: 90, noise: 84, heatHaze: 80, framing: 82)
    private static let e175Findings = findings(horizon: 88, sharpness: 62, exposure: 70, noise: 76, heatHaze: 68, framing: 80)
    private static let f22Findings = findings(horizon: 78, sharpness: 72, exposure: 58, noise: 66, heatHaze: 74, framing: 72)
    private static let fa18Findings = findings(horizon: 70, sharpness: 52, exposure: 60, noise: 58, heatHaze: 66, framing: 78)
    private static let b2Findings = findings(horizon: 84, sharpness: 78, exposure: 82, noise: 76, heatHaze: 80, framing: 80)

    /// The settings a sample photo was taken with. Every sample photo came
    /// from the same camera and lens.
    private static func camera(
        focalLength: Double,
        aperture: Double,
        exposureTime: Double,
        iso: Int
    ) -> CameraSettings {
        CameraSettings(
            cameraMake: "Canon",
            cameraModel: "Canon EOS R5",
            lensModel: "RF100-500mm F4.5-7.1 L IS USM",
            focalLength: focalLength,
            aperture: aperture,
            exposureTime: exposureTime,
            iso: iso
        )
    }

    private static let vc25Camera = camera(focalLength: 500, aperture: 7.1, exposureTime: 1.0 / 2000, iso: 12800)
    private static let b737Camera = camera(focalLength: 223, aperture: 5, exposureTime: 1.0 / 30, iso: 2500)
    private static let e175Camera = camera(focalLength: 223, aperture: 5, exposureTime: 1.0 / 40, iso: 2500)
    private static let f22Camera = camera(focalLength: 400, aperture: 8, exposureTime: 1.0 / 4000, iso: 640)
    private static let fa18Camera = camera(focalLength: 500, aperture: 8, exposureTime: 1.0 / 3200, iso: 1000)
    private static let b2Camera = camera(focalLength: 500, aperture: 7.1, exposureTime: 1.0 / 4000, iso: 1000)

    static let photos: [SpottedPhoto] = [
        SpottedPhoto(
            id: "vc25a-29000",
            imageName: "SampleVC25A",
            aircraftType: "Boeing VC-25A",
            registration: "29000",
            airline: "US Air Force",
            activity: "in a flyover",
            camera: vc25Camera,
            capturedAt: PhotoMetadataReader.captureDate(fromExif: "2026:07:04 19:18:20"),
            captureCoordinate: Coordinate(latitude: 33.6497, longitude: -84.4058),
            spotID: "atl-cargo-ramp",
            status: .graded(voteAverage: 4.55, voteCount: 18),
            findings: vc25Findings,
            fixes: stockFixes(for: vc25Findings)
        ),
        SpottedPhoto(
            id: "b737-n823ak",
            imageName: "SampleB737",
            aircraftType: "Boeing 737 MAX 8",
            registration: "N823AK",
            airline: "Alaska Airlines",
            activity: "on the runway at dusk",
            camera: b737Camera,
            capturedAt: PhotoMetadataReader.captureDate(fromExif: "2026:05:17 20:33:01"),
            captureCoordinate: Coordinate(latitude: 33.6221, longitude: -84.3998),
            spotID: "atl-south-approach",
            status: .graded(voteAverage: 4.4, voteCount: 12),
            findings: [
                finding(.horizon, 60, "It tilts 1.8° to the left. Rotate the crop to fix it."),
                finding(.sharpness, 70, "The nose is a little soft. Try 1/60 s or faster."),
                finding(.exposure, 90, "Highlights and shadows both hold detail."),
                finding(.noise, 86, "Clean for ISO 2500."),
                finding(.heatHaze, 82, "No shimmer along the fuselage."),
                finding(.framing, 80, "The whole aircraft is in frame with room ahead."),
            ],
            fixes: [
                SuggestedFix(
                    kind: .horizon,
                    title: "Straighten the horizon",
                    detail: "It tilts 1.8° to the left.",
                    points: 4
                ),
                SuggestedFix(
                    kind: .sharpness,
                    title: "Use a faster shutter",
                    detail: "The nose is a little soft at 1/30 s.",
                    points: 3
                ),
            ]
        ),
        SpottedPhoto(
            id: "e175-delta",
            imageName: "SampleE175",
            aircraftType: "Embraer E175",
            // The registration is partly hidden by the wing in the photo.
            registration: "",
            airline: "Delta Connection",
            activity: "touching down at dusk",
            camera: e175Camera,
            capturedAt: PhotoMetadataReader.captureDate(fromExif: "2026:05:17 20:31:21"),
            spotID: "atl-north-deck",
            status: .graded(voteAverage: 3.8, voteCount: 9),
            findings: e175Findings,
            fixes: stockFixes(for: e175Findings)
        ),
        SpottedPhoto(
            id: "f22-raptor",
            imageName: "SampleF22",
            aircraftType: "F-22 Raptor",
            registration: "",
            airline: "US Air Force",
            activity: "turning on afterburner",
            camera: f22Camera,
            capturedAt: PhotoMetadataReader.captureDate(fromExif: "2026:08:16 16:59:25"),
            isLocationUndisclosed: true,
            status: .graded(voteAverage: 3.55, voteCount: 7),
            findings: f22Findings,
            fixes: stockFixes(for: f22Findings)
        ),
        SpottedPhoto(
            id: "fa18-blue-angels-5",
            imageName: "SampleFA18",
            aircraftType: "F/A-18E Super Hornet",
            registration: "",
            airline: "US Navy Blue Angels",
            activity: "banking past",
            camera: fa18Camera,
            capturedAt: PhotoMetadataReader.captureDate(fromExif: "2026:06:20 14:59:48"),
            spotID: "atl-south-approach",
            status: .graded(voteAverage: 3.2, voteCount: 6),
            findings: fa18Findings,
            fixes: stockFixes(for: fa18Findings)
        ),
        SpottedPhoto(
            id: "b2-spirit",
            imageName: "SampleB2",
            aircraftType: "B-2 Spirit",
            registration: "",
            airline: "US Air Force",
            activity: "passing overhead",
            camera: b2Camera,
            capturedAt: PhotoMetadataReader.captureDate(fromExif: "2026:06:24 19:45:40"),
            captureCoordinate: Coordinate(latitude: 33.6389, longitude: -84.4569),
            spotID: "atl-west-road",
            status: .voting(votesIn: 3, hoursLeft: 31),
            findings: b2Findings,
            fixes: stockFixes(for: b2Findings)
        ),
    ]

    // MARK: Imported photos

    /// A picked photo with full metadata, for previews of the Add screen.
    static var importedPhoto: ImportedPhoto {
        ImportedPhoto(
            id: "preview-import",
            image: UIImage(named: "SampleB737") ?? UIImage(),
            metadata: PhotoMetadata(
                camera: b737Camera,
                capturedAt: PhotoMetadataReader.captureDate(fromExif: "2026:05:17 20:33:01"),
                coordinate: Coordinate(latitude: 33.6215, longitude: -84.3990)
            ),
            // What the text reader might find on the fuselage and tail.
            recognizedText: [
                RecognizedText(text: "Alaska", confidence: 0.98),
                RecognizedText(text: "N823AK", confidence: 0.86),
            ]
        )
    }

    /// A picked photo that carries no metadata, such as a screenshot or an
    /// export that stripped it.
    static var importedPhotoWithoutMetadata: ImportedPhoto {
        ImportedPhoto(
            id: "preview-import-bare",
            image: UIImage(named: "SampleE175") ?? UIImage(),
            metadata: .empty
        )
    }

    // MARK: Technical check

    /// What the device might measure in a soft photo with blown highlights.
    /// The framing is fine.
    static let softBrightMeasurements = PhotoMeasurements(
        subject: FrameRegion(x: 0.2, y: 0.3, width: 0.6, height: 0.35),
        subjectSource: .mask,
        sharpness: 80,
        blownHighlights: 0.12,
        crushedShadows: 0
    )

    /// A logged photo that has been through the technical check and has no
    /// grade yet, which is how a photo looks right after it is imported.
    static func checkedPhoto(in model: CollectionModel) -> SpottedPhoto {
        let check = model.technicalCheck(for: softBrightMeasurements, camera: vc25Camera)
        return SpottedPhoto(
            id: "preview-checked",
            imageName: "SampleVC25A",
            aircraftType: "Boeing VC-25A",
            registration: "29000",
            airline: "US Air Force",
            activity: "",
            camera: vc25Camera,
            status: .logged,
            findings: check.findings,
            fixes: check.fixes
        )
    }

    /// A logged photo in which the technical check found no aircraft, so
    /// it has no score.
    static let unfoundPhoto = SpottedPhoto(
        id: "preview-unfound",
        imageName: "SampleB2",
        aircraftType: "B-2 Spirit",
        registration: "",
        airline: "US Air Force",
        activity: "",
        camera: b2Camera,
        status: .logged,
        isAircraftFound: false
    )

    // MARK: Voting

    static let voteQueue: [VoteCandidate] = [
        VoteCandidate(id: "vote-e175", imageName: "SampleE175", aircraftType: "Embraer E175"),
        VoteCandidate(id: "vote-fa18", imageName: "SampleFA18", aircraftType: "F/A-18E Super Hornet"),
        VoteCandidate(id: "vote-b2", imageName: "SampleB2", aircraftType: "B-2 Spirit"),
        VoteCandidate(id: "vote-f22", imageName: "SampleF22", aircraftType: "F-22 Raptor"),
        VoteCandidate(id: "vote-vc25a", imageName: "SampleVC25A", aircraftType: "Boeing VC-25A"),
        VoteCandidate(id: "vote-b737", imageName: "SampleB737", aircraftType: "Boeing 737 MAX 8"),
    ]

    // MARK: Spots

    static let airports: [Airport] = [
        Airport(
            id: "ATL",
            city: "Atlanta",
            latitude: 33.6407,
            longitude: -84.4277,
            spots: [
                Spot(
                    id: "atl-south-approach",
                    name: "South approach",
                    summary: "Arrivals pass low from the east. The light is best in the afternoon.",
                    latitude: 33.6215,
                    longitude: -84.3990,
                    photoCount: 128,
                    photoNames: ["SampleB737", "SampleVC25A", "SampleFA18"]
                ),
                Spot(
                    id: "atl-cargo-ramp",
                    name: "Cargo ramp fence",
                    summary: "Freighters taxi past at close range. Bring a wide lens.",
                    latitude: 33.6492,
                    longitude: -84.4065,
                    photoCount: 64,
                    photoNames: ["SampleVC25A", "SampleE175", "SampleF22"]
                ),
                Spot(
                    id: "atl-north-deck",
                    name: "North deck",
                    summary: "A raised deck with a clear view of the north runways.",
                    latitude: 33.6568,
                    longitude: -84.4310,
                    photoCount: 31,
                    photoNames: ["SampleE175", "SampleB2", "SampleF22"]
                ),
                Spot(
                    id: "atl-west-road",
                    name: "West road",
                    summary: "A quiet road beside the west end of the runways.",
                    latitude: 33.6395,
                    longitude: -84.4575,
                    photoCount: 12,
                    photoNames: ["SampleB2", "SampleFA18", "SampleB737"]
                ),
            ]
        ),
        Airport(
            id: "SEA",
            city: "Seattle",
            latitude: 47.4502,
            longitude: -122.3088,
            spots: [
                Spot(
                    id: "sea-south-end",
                    name: "South end",
                    summary: "Departures climb overhead when the wind is from the north.",
                    latitude: 47.4285,
                    longitude: -122.3085,
                    photoCount: 47,
                    photoNames: ["SampleF22", "SampleE175", "SampleB2"]
                ),
                Spot(
                    id: "sea-east-hill",
                    name: "East hill",
                    summary: "A long view across all three runways with the mountains behind.",
                    latitude: 47.4520,
                    longitude: -122.2920,
                    photoCount: 22,
                    photoNames: ["SampleFA18", "SampleB737", "SampleVC25A"]
                ),
            ]
        ),
    ]

    // MARK: Helpers

    private static func finding(_ kind: CheckKind, _ score: Double, _ detail: String) -> CheckFinding {
        // Sample scores are constants inside 0 to 100, so the result exists.
        CheckFinding(result: CheckResult(kind: kind, score: score)!, detail: detail)
    }

    /// Builds six findings with stock wording for each check.
    private static func findings(
        horizon: Double,
        sharpness: Double,
        exposure: Double,
        noise: Double,
        heatHaze: Double,
        framing: Double
    ) -> [CheckFinding] {
        let scores: [(CheckKind, Double)] = [
            (.horizon, horizon),
            (.sharpness, sharpness),
            (.exposure, exposure),
            (.noise, noise),
            (.heatHaze, heatHaze),
            (.framing, framing),
        ]
        return scores.map { kind, score in
            finding(kind, score, stockDetail(for: kind, passed: score >= passingCheckScore))
        }
    }

    /// Builds a fix for every finding under the passing score, with the
    /// largest gain first. The points are placeholders.
    private static func stockFixes(for findings: [CheckFinding]) -> [SuggestedFix] {
        findings
            .filter { $0.result.score < passingCheckScore }
            .map { finding in
                let gap = passingCheckScore + 5 - finding.result.score
                return SuggestedFix(
                    kind: finding.result.kind,
                    title: stockFixTitle(for: finding.result.kind),
                    detail: stockFixDetail(for: finding.result.kind),
                    points: max(1, Int((gap / 5).rounded()))
                )
            }
            .sorted { $0.points > $1.points }
    }

    private static func stockFixTitle(for kind: CheckKind) -> String {
        switch kind {
        case .horizon: "Straighten the horizon"
        case .sharpness: "Use a faster shutter"
        case .exposure: "Adjust the exposure"
        case .noise: "Lower the ISO"
        case .heatHaze: "Shoot in cooler air"
        case .framing: "Leave room ahead"
        }
    }

    private static func stockFixDetail(for kind: CheckKind) -> String {
        switch kind {
        case .horizon: "The horizon tilts."
        case .sharpness: "The aircraft is a little soft."
        case .exposure: "Parts of the aircraft lose detail."
        case .noise: "Grain shows in the sky."
        case .heatHaze: "Heat shimmer blurs the fuselage."
        case .framing: "The aircraft sits tight in the frame."
        }
    }

    private static func stockDetail(for kind: CheckKind, passed: Bool) -> String {
        switch (kind, passed) {
        case (.horizon, true): "The horizon is level."
        case (.horizon, false): "The horizon tilts. Rotate the crop to level it."
        case (.sharpness, true): "The aircraft is sharp from nose to tail."
        case (.sharpness, false): "The aircraft is a little soft. Try a faster shutter speed."
        case (.exposure, true): "Highlights and shadows both hold detail."
        case (.exposure, false): "Parts of the aircraft lose detail. Adjust the exposure."
        case (.noise, true): "The image is clean."
        case (.noise, false): "Grain shows in the sky. Use a lower ISO."
        case (.heatHaze, true): "No shimmer along the fuselage."
        case (.heatHaze, false): "Heat shimmer blurs the fuselage. Shoot in cooler air or from closer."
        case (.framing, true): "The whole aircraft is in frame with room ahead."
        case (.framing, false): "The aircraft sits tight in the frame. Leave room ahead of the nose."
        }
    }
}
