import FinalApproachCore
import Foundation

/// Says which aircraft were flying near a place at one minute.
///
/// The real provider is reached through the backend, which keeps its key.
/// It sits behind this protocol so screens can be built and previewed with
/// sample data.
protocol FlightDataProvider {
    func flights(near place: Coordinate, at time: Date) async throws -> [FlightSighting]
}

/// A provider that answers with the same sample aircraft every time. It is
/// for previews and tests only. A real photo must never be matched against
/// it, because it would suggest an aircraft that was not there.
struct SampleFlightDataProvider: FlightDataProvider {
    let sightings: [FlightSighting]

    func flights(near place: Coordinate, at time: Date) async throws -> [FlightSighting] {
        sightings
    }
}
