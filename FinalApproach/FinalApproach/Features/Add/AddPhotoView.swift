import FinalApproachCore
import Foundation
import SwiftUI

/// Logs a photo picked from the library. It shows what was read from the
/// photo, takes the aircraft details, and lets the user keep the location
/// private. Logging the photo also scores its technical check, saves it on
/// the device, and links it to the nearest listed spot.
///
/// The screen suggests the aircraft from the registration read off the
/// photo and from what was flying there. It fills the fields by itself only
/// when both agree. A registration that was only read is offered for the
/// user to tap, because part of it may be hidden in the photo. The user can
/// change every field, and may leave them all empty for an aircraft they
/// cannot name. A photo with no saved location can be placed with a pin on
/// a map.
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
    /// The details the app last filled in from a flight. A field that still
    /// holds one of them was not typed by the user, so another flight may
    /// replace or clear it.
    @State private var filledType: String?
    @State private var filledRegistration: String?
    @State private var filledAirline: String?
    /// Where the user pinned the photo, for one that carries no location.
    @State private var pinnedPlace: Coordinate?
    @State private var isPickingPlace = false

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
        // A pin gives the flight lookup a place, so it runs again.
        .task(id: pinnedPlace) {
            await identify()
        }
        .sheet(isPresented: $isPickingPlace) {
            PlacePickerView(
                // The map opens on the pin, or where the user's last photo
                // was taken, since photos are often logged a few at a time.
                // The sample photos are not the user's, so they do not count.
                start: pinnedPlace ?? model.locatedPhotos.first { !$0.isSample }?.ownerCaptureCoordinate,
                hasPin: pinnedPlace != nil
            ) { place in
                withAnimation(Motion.swap) {
                    pinnedPlace = place
                }
            }
        }
    }

    // MARK: Sections

    private var aircraftFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeading("Aircraft")
                Text("Leave these empty if you do not know the aircraft. You can add them later.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
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

    /// How many registrations read off the photo to offer.
    private static let readingLimit = 3

    /// What the app worked out about the aircraft. Tapping a row fills the
    /// fields from it.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Suggested")
            ForEach(identification.readings.prefix(Self.readingLimit)) { reading in
                SuggestionRow(
                    systemImage: "text.viewfinder",
                    title: reading.registration,
                    detail: "Read off the aircraft. Check it, as part may be hidden. Registered in \(reading.country).",
                    isChosen: trimmed(registration).uppercased() == reading.registration
                ) {
                    withAnimation(Motion.press) {
                        registration = reading.registration
                    }
                }
                .accessibilityHint("Fills in the registration")
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
        Button {
            isPickingPlace = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pinnedPlace == nil ? "Where was this taken?" : "Move the pin")
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                    Text(pinnedPlace == nil ? "Drop a pin on the map." : "Change or remove where this was taken.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TilePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens a map")
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

    /// The pin the user dropped, when the photo carries no location.
    private var pin: Coordinate? {
        photo.metadata.coordinate == nil ? pinnedPlace : nil
    }

    /// Where the photo was taken, from the file or from the pin.
    private var place: Coordinate? {
        photo.metadata.coordinate ?? pin
    }

    /// The listed spot the photo was taken near, when there is one.
    private var nearestSpot: Spot? {
        place.flatMap { model.nearestSpot(to: $0) }
    }

    private var locationText: String {
        guard place != nil else { return "No location" }
        if pin != nil {
            return nearestSpot.map { "Pinned near \($0.name)" } ?? "Pinned on the map"
        }
        return nearestSpot.map { "Near \($0.name)" } ?? "Location saved"
    }

    private var locationDetail: String {
        if pin != nil { return "Where you said it was taken" }
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
        // Only a flight that the registration confirms is filled in
        // without a tap. A registration that was only read may be cut
        // short by a wing or a winglet, so the user picks it.
        if let confirmed = result.confirmedFlight {
            apply(confirmed.sighting, replacingTypedDetails: false)
        }
    }

    /// Fills the fields from a flight. A suggestion made by the app never
    /// writes over what the user typed. A flight the user tapped does.
    ///
    /// A detail the flight does not carry clears a field that still holds
    /// what an earlier flight filled in, so one aircraft's details are
    /// never logged with another's flight.
    private func apply(_ sighting: FlightSighting, replacingTypedDetails: Bool) {
        aircraftType = filled(
            aircraftType, from: sighting.aircraftType, lastFilled: filledType, replacing: replacingTypedDetails
        )
        registration = filled(
            registration, from: sighting.registration, lastFilled: filledRegistration, replacing: replacingTypedDetails
        )
        airline = filled(
            airline, from: sighting.airline, lastFilled: filledAirline, replacing: replacingTypedDetails
        )
        filledType = sighting.aircraftType
        filledRegistration = sighting.registration
        filledAirline = sighting.airline
        chosenFlightID = sighting.id
    }

    /// What one field should hold after a flight is applied.
    private func filled(_ current: String, from value: String?, lastFilled: String?, replacing: Bool) -> String {
        if let value {
            return replacing || trimmed(current).isEmpty ? value : current
        }
        // The flight does not know this detail. What an earlier flight
        // filled in goes, and what the user typed stays.
        return current == lastFilled ? "" : current
    }

    /// The flight and route of the chosen flight, such as "flight AS331
    /// from SEA to ATL", or an empty string when none is chosen.
    private var chosenActivity: String {
        identification.flights.first { $0.id == chosenFlightID }?.sighting.activity ?? ""
    }

    // MARK: Logging

    private func log() {
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

/// One suggestion the user can tap to fill the fields, with a check mark
/// when it is the one in use.
private struct SuggestionRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let isChosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
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
        .accessibilityAddTraits(isChosen ? .isSelected : [])
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

    /// The flight and its route with a capital, such as "Flight DAL1482".
    private var flightText: String {
        let activity = flight.sighting.activity
        return activity.prefix(1).uppercased() + activity.dropFirst()
    }

    /// The aircraft type, or the flight when the provider gave only a
    /// callsign.
    private var title: String {
        flight.sighting.aircraftType ?? flightText
    }

    private var detail: String {
        let distance = Measurement(value: flight.distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        // The flight is already the title when there is no type.
        let activity: String? = flight.sighting.aircraftType == nil ? nil : flight.sighting.activity
        let parts = [flight.sighting.airline, activity, "\(distance) away"].compactMap { $0 }
        let line = parts.joined(separator: ", ")
        return isConfirmed ? "Matches the registration. \(line)" : line
    }

    var body: some View {
        SuggestionRow(
            systemImage: "airplane",
            title: title,
            detail: detail,
            isChosen: isChosen,
            choose: choose
        )
        .accessibilityHint("Fills in the aircraft details")
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
