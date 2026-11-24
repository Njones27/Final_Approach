import FinalApproachCore
import Foundation
import Testing
import UIKit

@testable import FinalApproach

/// Working out the aircraft in a picked photo, from the text read off it
/// and from the sample flight data.
@MainActor
struct IdentificationTests {
    private let flightData = SampleFlightDataProvider(sightings: SampleData.flights)
    private let southApproach = Coordinate(latitude: 33.6215, longitude: -84.3990)

    @Test func aRegistrationReadOffThePhotoConfirmsItsFlight() async throws {
        let model = SampleData.model(flightData: flightData)
        let place = try #require(southApproach)
        let result = await model.identification(for: SampleData.importedPhoto, at: place)

        #expect(result.readings.map(\.registration) == ["N823AK"])
        #expect(result.confirmedFlight?.sighting.registration == "N823AK")
        // The aircraft at cruising height is left out.
        #expect(result.flights.map(\.id) == ["sample-asa", "sample-dal", "sample-skw"])
        #expect(result.confirmedFlight?.sighting.activity == "flight AS331 from SEA to ATL")
    }

    @Test func theAppItselfHasNoFlightDataYet() async throws {
        // A real photo must never be matched against sample aircraft.
        let model = SampleData.model()
        let place = try #require(southApproach)
        let result = await model.identification(for: SampleData.importedPhoto, at: place)

        #expect(result.readings.map(\.registration) == ["N823AK"])
        #expect(result.flights.isEmpty)
        #expect(result.confirmedFlight == nil)
    }

    @Test func aPhotoWithNoPlaceGetsNoFlights() async {
        let model = SampleData.model(flightData: flightData)
        let result = await model.identification(for: SampleData.importedPhoto, at: nil)

        #expect(result.readings.map(\.registration) == ["N823AK"])
        #expect(result.flights.isEmpty)
    }

    @Test func aPhotoWithNoCaptureTimeGetsNoFlights() async throws {
        let model = SampleData.model(flightData: flightData)
        let place = try #require(southApproach)
        let result = await model.identification(for: SampleData.importedPhotoWithoutMetadata, at: place)

        #expect(result.isEmpty)
    }

    @Test func aBlockedRegistrationIsNeverSuggested() async throws {
        let model = SampleData.model(
            flightData: flightData,
            blockList: RegistrationBlockList(registrations: ["n823ak"])
        )
        let place = try #require(southApproach)
        let result = await model.identification(for: SampleData.importedPhoto, at: place)

        #expect(result.readings.isEmpty)
        #expect(result.flights.map(\.id) == ["sample-dal", "sample-skw"])
        #expect(result.confirmedFlight == nil)
        #expect(model.isBlocked(registration: "N823AK"))
        #expect(!model.isBlocked(registration: "N8642E"))
    }

    @Test func theSampleFormatsReadCommonRegistrations() {
        let texts = ["N8642E", "G-EUUU", "C-FIVS", "D-AIMA", "JA873A", "VH-OQA", "DELTA", "NAVY"]
            .map { RecognizedText(text: $0, confidence: 0.9) }
        let readings = RegistrationReader.readings(in: texts, formats: SampleData.registrationFormats)
        #expect(readings.map(\.registration) == ["N8642E", "G-EUUU", "C-FIVS", "D-AIMA", "JA873A", "VH-OQA"])
    }
}
