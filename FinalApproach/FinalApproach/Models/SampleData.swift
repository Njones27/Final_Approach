import FinalApproachCore
import Foundation

/// Sample data for previews and for running the app before a backend exists.
///
/// The photos are drawn stand-ins, the spots are invented, and the tier
/// thresholds and passing score are placeholders until the product decides
/// the real values.
enum SampleData {
    /// Placeholder tier thresholds.
    static let thresholds = TierThresholds(bronze: 50, silver: 65, gold: 80)!
    /// Placeholder passing score for one technical check.
    static let passingCheckScore = 75.0

    static func model() -> CollectionModel {
        CollectionModel(
            photos: photos,
            profile: profile,
            voteQueue: voteQueue,
            airports: airports,
            thresholds: thresholds,
            passingCheckScore: passingCheckScore,
            flightData: SampleFlightDataProvider()
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

    private static let b748Findings = findings(horizon: 92, sharpness: 88, exposure: 90, noise: 84, heatHaze: 80, framing: 82)
    private static let b737Findings = findings(horizon: 88, sharpness: 62, exposure: 70, noise: 76, heatHaze: 68, framing: 80)
    private static let e175Findings = findings(horizon: 78, sharpness: 72, exposure: 58, noise: 66, heatHaze: 74, framing: 72)
    private static let b787Findings = findings(horizon: 70, sharpness: 52, exposure: 60, noise: 58, heatHaze: 66, framing: 78)
    private static let a220Findings = findings(horizon: 84, sharpness: 78, exposure: 82, noise: 76, heatHaze: 80, framing: 80)

    static let photos: [SpottedPhoto] = [
        SpottedPhoto(
            id: "b748-n605up",
            imageName: "SampleB748",
            aircraftType: "Boeing 747-8F",
            registration: "N605UP",
            airline: "UPS",
            activity: "landing at dusk",
            spotID: "atl-cargo-ramp",
            status: .graded(voteAverage: 4.55, voteCount: 18),
            findings: b748Findings,
            fixes: stockFixes(for: b748Findings)
        ),
        SpottedPhoto(
            id: "a350-n502dn",
            imageName: "SampleA350",
            aircraftType: "Airbus A350-900",
            registration: "N502DN",
            airline: "Delta Air Lines",
            activity: "landing at Atlanta",
            spotID: "atl-south-approach",
            status: .graded(voteAverage: 4.4, voteCount: 12),
            findings: [
                finding(.horizon, 60, "It tilts 1.8° to the left. Rotate the crop to fix it."),
                finding(.sharpness, 70, "The nose is a little soft. Try 1/1000 s or faster."),
                finding(.exposure, 90, "Highlights and shadows both hold detail."),
                finding(.noise, 86, "Clean at ISO 200."),
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
                    detail: "The nose is a little soft at 1/640 s.",
                    points: 3
                ),
            ]
        ),
        SpottedPhoto(
            id: "b737-n8642e",
            imageName: "SampleB737",
            aircraftType: "Boeing 737-800",
            registration: "N8642E",
            airline: "Southwest Airlines",
            activity: "climbing out of Atlanta",
            spotID: "atl-north-deck",
            status: .graded(voteAverage: 3.8, voteCount: 9),
            findings: b737Findings,
            fixes: stockFixes(for: b737Findings)
        ),
        SpottedPhoto(
            id: "e175-n620qx",
            imageName: "SampleE175",
            aircraftType: "Embraer E175",
            registration: "N620QX",
            airline: "Horizon Air",
            activity: "taking off",
            isLocationUndisclosed: true,
            status: .graded(voteAverage: 3.55, voteCount: 7),
            findings: e175Findings,
            fixes: stockFixes(for: e175Findings)
        ),
        SpottedPhoto(
            id: "b787-n27965",
            imageName: "SampleB787",
            aircraftType: "Boeing 787-9",
            registration: "N27965",
            airline: "United Airlines",
            activity: "on approach at sunset",
            spotID: "atl-south-approach",
            status: .graded(voteAverage: 3.2, voteCount: 6),
            findings: b787Findings,
            fixes: stockFixes(for: b787Findings)
        ),
        SpottedPhoto(
            id: "a220-n3008j",
            imageName: "SampleA220",
            aircraftType: "Airbus A220-300",
            registration: "N3008J",
            airline: "JetBlue",
            activity: "on final approach",
            spotID: "atl-west-road",
            status: .voting(votesIn: 3, hoursLeft: 31),
            findings: a220Findings,
            fixes: stockFixes(for: a220Findings)
        ),
    ]

    // MARK: Voting

    static let voteQueue: [VoteCandidate] = [
        VoteCandidate(id: "vote-b737", imageName: "SampleB737", aircraftType: "Boeing 737-800"),
        VoteCandidate(id: "vote-b787", imageName: "SampleB787", aircraftType: "Boeing 787-9"),
        VoteCandidate(id: "vote-e175", imageName: "SampleE175", aircraftType: "Embraer E175"),
        VoteCandidate(id: "vote-a220", imageName: "SampleA220", aircraftType: "Airbus A220-300"),
        VoteCandidate(id: "vote-b748", imageName: "SampleB748", aircraftType: "Boeing 747-8F"),
        VoteCandidate(id: "vote-a350", imageName: "SampleA350", aircraftType: "Airbus A350-900"),
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
                    photoNames: ["SampleA350", "SampleB748", "SampleB787"]
                ),
                Spot(
                    id: "atl-cargo-ramp",
                    name: "Cargo ramp fence",
                    summary: "Freighters taxi past at close range. Bring a wide lens.",
                    latitude: 33.6492,
                    longitude: -84.4065,
                    photoCount: 64,
                    photoNames: ["SampleB748", "SampleB737", "SampleE175"]
                ),
                Spot(
                    id: "atl-north-deck",
                    name: "North deck",
                    summary: "A raised deck with a clear view of the north runways.",
                    latitude: 33.6568,
                    longitude: -84.4310,
                    photoCount: 31,
                    photoNames: ["SampleB737", "SampleA220", "SampleE175"]
                ),
                Spot(
                    id: "atl-west-road",
                    name: "West road",
                    summary: "A quiet road beside the west end of the runways.",
                    latitude: 33.6395,
                    longitude: -84.4575,
                    photoCount: 12,
                    photoNames: ["SampleA220", "SampleB787", "SampleA350"]
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
                    photoNames: ["SampleE175", "SampleB737", "SampleA220"]
                ),
                Spot(
                    id: "sea-east-hill",
                    name: "East hill",
                    summary: "A long view across all three runways with the mountains behind.",
                    latitude: 47.4520,
                    longitude: -122.2920,
                    photoCount: 22,
                    photoNames: ["SampleB787", "SampleA350", "SampleB748"]
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
