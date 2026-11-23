import Foundation

/// One piece of evidence that ties a photo to a flight.
struct MatchEvidence: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let source: String
}

/// The aircraft a new photo was matched to, with the reasons for the match.
struct FlightMatch {
    let photo: SpottedPhoto
    let evidence: [MatchEvidence]
}

/// Looks up which aircraft a photo shows.
///
/// The real implementation will call the backend, which holds the flight
/// data provider key. Screens depend on this protocol so they can be built
/// and previewed with sample data.
protocol FlightDataProvider {
    /// Returns the best match for the photo being added, or nil when nothing
    /// matched.
    func matchNewPhoto() async throws -> FlightMatch?
}

/// Returns a fixed match so the Add screen works with no backend.
struct SampleFlightDataProvider: FlightDataProvider {
    func matchNewPhoto() async throws -> FlightMatch? {
        FlightMatch(
            photo: SpottedPhoto(
                id: "new-a350-\(UUID().uuidString)",
                imageName: "SampleA350",
                aircraftType: "Airbus A350-900",
                registration: "N502DN",
                airline: "Delta Air Lines",
                activity: "arriving from Seoul",
                spotID: "atl-south-approach",
                status: .logged
            ),
            evidence: [
                MatchEvidence(
                    id: "time-place",
                    systemImage: "clock",
                    title: "5:42 PM on 14 Nov, at Atlanta",
                    source: "Time and place saved in the photo"
                ),
                MatchEvidence(
                    id: "flight-data",
                    systemImage: "airplane.arrival",
                    title: "One arrival on final at that minute",
                    source: "Flight data lookup"
                ),
                MatchEvidence(
                    id: "registration",
                    systemImage: "text.viewfinder",
                    title: "N502DN painted on the fuselage",
                    source: "Read from the photo on your iPhone"
                ),
            ]
        )
    }
}
