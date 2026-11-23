import FinalApproachCore
import Foundation
import SwiftUI

/// Logs a photo picked from the library. It shows what was read from the
/// photo, takes the aircraft details, and lets the user keep the location
/// private. Logging the photo also scores its technical check, saves it on
/// the device, and links it to the nearest listed spot.
///
/// The screen suggests the aircraft from the registration read off the
/// photo and from what was flying there, and fills in what it is sure of.
/// The user can change every field. A photo with no saved location can be
/// tagged with a listed spot.
struct AddPhotoView: View {
    let photo: ImportedPhoto

    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LocationPrivacySetting.storageKey) private var privacySetting = LocationPrivacySetting.askEachTime
    @State private var aircraftType = ""
    @State private var registration = ""
    @State private var airline = ""
    @State private var showsSpot = true
    @State private var identification = Identification.none
    /// The flight the details came from, picked by the user or confirmed by
    /// the registration.
    @State private var chosenFlightID: String?
    /// The spot the user tagged, for a photo that carries no location.
    @State private var taggedSpotID: String?

    /// A photo can be logged once it has an aircraft type.
    private var canLog: Bool {
        !trimmed(aircraftType).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PhotoFill(image: Image(uiImage: photo.image), description: "The photo you picked")
                        .aspectRatio(3 / 2, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 24) {
                        if !identification.isEmpty {
                            suggestions
                                .transition(.opacity)
                        }
                        aircraftFields
                        photoFacts
                        if photo.metadata.coordinate == nil {
                            locationTag
                        }
                        if place != nil {
                            locationSwitch
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button("Log this photo") {
                    log()
                }
                .buttonStyle(.primary)
                .opacity(canLog ? 1 : 0.4)
                .animation(Motion.press, value: canLog)
                .disabled(!canLog)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.ground)
            }
            .background(Theme.ground)
            .navigationTitle("New photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            showsSpot = privacySetting.showsSpotByDefault
        }
        // Tagging a spot gives the flight lookup a place, so it runs again.
        .task(id: taggedSpotID) {
            await identify()
        }
    }

    // MARK: Sections

    private var aircraftFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading("Aircraft")
            DetailField(label: "Type", prompt: "Boeing 737-800", text: $aircraftType)
            DetailField(
                label: "Registration",
                prompt: "N8642E",
                text: $registration,
                capitalization: .characters
            )
            DetailField(label: "Airline", prompt: "Southwest Airlines", text: $airline)
        }
    }

    /// What the app worked out about the aircraft. Tapping a flight fills
    /// the fields from it.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Suggested")
            if let reading = identification.readings.first {
                FactRow(
                    systemImage: "text.viewfinder",
                    title: reading.registration,
                    detail: "Read off the aircraft. Registered in \(reading.country)."
                )
            }
            ForEach(identification.flights) { flight in
                FlightRow(
                    flight: flight,
                    isChosen: flight.id == chosenFlightID,
                    isConfirmed: flight.id == identification.confirmedFlight?.id
                ) {
                    withAnimation(Motion.press) {
                        apply(flight.sighting, replacingTypedDetails: true)
                    }
                }
            }
        }
    }

    private var photoFacts: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Read from the photo")
            FactRow(
                systemImage: "clock",
                title: captureTimeText ?? "No capture time",
                detail: captureTimeText == nil ? "The photo does not carry one." : "When it was taken"
            )
            FactRow(
                systemImage: place == nil ? "location.slash" : "location",
                title: locationText,
                detail: locationDetail
            )
            FactRow(
                systemImage: "camera",
                title: cameraText ?? "No camera settings",
                detail: cameraText == nil ? "The photo does not carry any." : "Camera and settings"
            )
        }
    }

    /// Lets the user say where a photo with no saved location was taken.
    private var locationTag: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where was this taken?")
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Text("Pick the spot you shot from.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            Picker("Spot", selection: $taggedSpotID) {
                Text("Not tagged").tag(String?.none)
                ForEach(model.airports) { airport in
                    Section(airport.displayName) {
                        ForEach(airport.spots) { spot in
                            Text(spot.name).tag(String?.some(spot.id))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.ink)
        }
    }

    private var locationSwitch: some View {
        VStack(alignment: .leading, spacing: 18) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
            Toggle(isOn: $showsSpot) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show the spot to other people")
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                    Text("Turn this off to keep the location private.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.switchOn)
        }
    }

    // MARK: Text

    /// The spot the user tagged, when the photo carries no location.
    private var taggedSpot: Spot? {
        guard photo.metadata.coordinate == nil else { return nil }
        return taggedSpotID.flatMap { model.spot(id: $0) }
    }

    /// Where the photo was taken, from the file or from the tagged spot.
    private var place: Coordinate? {
        photo.metadata.coordinate ?? taggedSpot?.coordinate
    }

    /// The listed spot the photo was taken near, when there is one.
    private var nearestSpot: Spot? {
        if let taggedSpot { return taggedSpot }
        return place.flatMap { model.nearestSpot(to: $0) }
    }

    private var locationText: String {
        if let taggedSpot { return "Tagged at \(taggedSpot.name)" }
        guard place != nil else { return "No location" }
        guard let nearestSpot else { return "Location saved" }
        return "Near \(nearestSpot.name)"
    }

    private var locationDetail: String {
        if taggedSpot != nil { return "Where you said it was taken" }
        return place == nil ? "The photo does not carry one." : "Where it was taken"
    }

    private var captureTimeText: String? {
        photo.metadata.capturedAt?.formatted(date: .abbreviated, time: .shortened)
    }

    /// The camera and its settings on one line, or nil when there are none.
    private var cameraText: String? {
        guard let camera = photo.metadata.camera else { return nil }
        let parts = [
            camera.cameraName,
            camera.focalLengthText,
            camera.apertureText,
            camera.shutterText,
            camera.isoText,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Identification

    /// Works out the aircraft and fills in what the user has not typed.
    private func identify() async {
        let result = await model.identification(for: photo, at: place)
        withAnimation(Motion.swap) {
            identification = result
            if let chosenFlightID, !result.flights.contains(where: { $0.id == chosenFlightID }) {
                self.chosenFlightID = nil
            }
        }
        if let confirmed = result.confirmedFlight {
            apply(confirmed.sighting, replacingTypedDetails: false)
        }
        if trimmed(registration).isEmpty, let reading = result.readings.first {
            registration = reading.registration
        }
    }

    /// Fills the fields from a flight. A suggestion made by the app never
    /// writes over what the user typed. A flight the user tapped does.
    private func apply(_ sighting: FlightSighting, replacingTypedDetails: Bool) {
        if let value = sighting.aircraftType, replacingTypedDetails || trimmed(aircraftType).isEmpty {
            aircraftType = value
        }
        if let value = sighting.registration, replacingTypedDetails || trimmed(registration).isEmpty {
            registration = value
        }
        if let value = sighting.airline, replacingTypedDetails || trimmed(airline).isEmpty {
            airline = value
        }
        chosenFlightID = sighting.id
    }

    /// The flight and route of the chosen flight, such as "flight AS331
    /// from SEA to ATL", or an empty string when none is chosen.
    private var chosenActivity: String {
        identification.flights.first { $0.id == chosenFlightID }?.sighting.activity ?? ""
    }

    // MARK: Logging

    private func log() {
        guard canLog else { return }
        let check = model.technicalCheck(for: photo.measurements, camera: photo.metadata.camera)
        let typedRegistration = trimmed(registration).uppercased()
        let spotted = SpottedPhoto(
            id: photo.id,
            imageName: nil,
            aircraftType: trimmed(aircraftType),
            registration: typedRegistration,
            // A blocked registration is kept with the photo and never shown.
            isRegistrationBlocked: model.isBlocked(registration: typedRegistration),
            airline: trimmed(airline),
            activity: chosenActivity,
            camera: photo.metadata.camera,
            capturedAt: photo.metadata.capturedAt,
            loggedAt: Date.now,
            captureCoordinate: place,
            spotID: nearestSpot?.id,
            isLocationUndisclosed: place != nil && !showsSpot,
            status: .logged,
            findings: check.findings,
            fixes: check.fixes,
            isAircraftFound: photo.measurements.subject != nil
        )
        model.add(spotted, image: photo.image)
        dismiss()
    }
}

/// A labeled text field with a hairline under it.
private struct DetailField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var capitalization: TextInputAutocapitalization = .words

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            TextField(label, text: $text, prompt: Text(prompt))
                .font(.body)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .frame(minHeight: 28)
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
    }
}

/// One thing read from the photo, with a short note under it.
private struct FactRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One aircraft that was flying near the photo. Tapping it fills the
/// fields from it.
private struct FlightRow: View {
    let flight: RankedFlight
    let isChosen: Bool
    /// True when the registration read off the photo matches this flight.
    let isConfirmed: Bool
    let choose: () -> Void

    private var title: String {
        flight.sighting.aircraftType ?? flight.sighting.callsign
    }

    private var detail: String {
        let distance = Measurement(value: flight.distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        let parts = [flight.sighting.airline, flight.sighting.activity, "\(distance) away"].compactMap { $0 }
        let line = parts.joined(separator: ", ")
        return isConfirmed ? "Matches the registration. \(line)" : line
    }

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "airplane")
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .opacity(isChosen ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TilePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Fills in the aircraft details")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

#Preview("Full metadata") {
    AddPhotoView(photo: SampleData.importedPhoto)
        .environment(SampleData.model(flightData: SampleFlightDataProvider(sightings: SampleData.flights)))
}

#Preview("No metadata") {
    AddPhotoView(photo: SampleData.importedPhotoWithoutMetadata)
        .environment(SampleData.model())
}
