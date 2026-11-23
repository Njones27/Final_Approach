import FinalApproachCore
import Foundation
import SwiftUI

/// Logs a photo picked from the library. It shows what was read from the
/// photo, takes the aircraft details, and lets the user keep the location
/// private. Logging the photo also scores its technical check. Automatic
/// identification replaces the typed details in the identification
/// milestone.
struct AddPhotoView: View {
    let photo: ImportedPhoto

    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LocationPrivacySetting.storageKey) private var privacySetting = LocationPrivacySetting.askEachTime
    @State private var aircraftType = ""
    @State private var registration = ""
    @State private var airline = ""
    @State private var showsSpot = true

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
                        aircraftFields
                        photoFacts
                        if photo.metadata.coordinate != nil {
                            locationSwitch
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

    private var photoFacts: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading("Read from the photo")
            FactRow(
                systemImage: "clock",
                title: captureTimeText ?? "No capture time",
                detail: captureTimeText == nil ? "The photo does not carry one." : "When it was taken"
            )
            FactRow(
                systemImage: photo.metadata.coordinate == nil ? "location.slash" : "location",
                title: photo.metadata.coordinate == nil ? "No location" : "Location saved",
                detail: photo.metadata.coordinate == nil
                    ? "The photo does not carry one."
                    : "Where it was taken"
            )
            FactRow(
                systemImage: "camera",
                title: cameraText ?? "No camera settings",
                detail: cameraText == nil ? "The photo does not carry any." : "Camera and settings"
            )
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

    // MARK: Logging

    private func log() {
        guard canLog else { return }
        let check = model.technicalCheck(for: photo.measurements, camera: photo.metadata.camera)
        let spotted = SpottedPhoto(
            id: photo.id,
            imageName: nil,
            aircraftType: trimmed(aircraftType),
            registration: trimmed(registration).uppercased(),
            airline: trimmed(airline),
            activity: "",
            camera: photo.metadata.camera,
            capturedAt: photo.metadata.capturedAt,
            captureCoordinate: photo.metadata.coordinate,
            isLocationUndisclosed: photo.metadata.coordinate != nil && !showsSpot,
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

#Preview("Full metadata") {
    AddPhotoView(photo: SampleData.importedPhoto)
        .environment(SampleData.model())
}

#Preview("No metadata") {
    AddPhotoView(photo: SampleData.importedPhotoWithoutMetadata)
        .environment(SampleData.model())
}
