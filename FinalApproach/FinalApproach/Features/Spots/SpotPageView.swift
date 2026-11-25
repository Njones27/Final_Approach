import FinalApproachCore
import SwiftUI

/// One note about a spot, such as how to get there.
struct SpotNote: Identifiable, Equatable {
    let title: String
    let text: String

    var id: String { title }
}

/// The page of one spot. It opens on the top voted photo people chose to
/// show from it, then says when the light is good, how to get there, and
/// what the place asks of a visitor, and then shows the rest of the photos.
///
/// A photo here is another person's. It comes with its grade, its tier,
/// and the aircraft type, airline, and camera settings its owner chose to
/// show. There is no photographer and no registration, and a photo whose
/// owner kept the location private never appears.
struct SpotPageView: View {
    let spotID: String

    @Environment(CollectionModel.self) private var model
    @Environment(SpotsModel.self) private var spots
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let spot = model.spot(id: spotID) {
                content(for: spot)
                    .navigationTitle(spot.name)
            } else {
                ContentUnavailableView(
                    "Spot not found",
                    systemImage: "mappin.slash",
                    description: Text("This spot is no longer listed.")
                )
            }
        }
        .background(Theme.ground)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for spot: Spot) -> some View {
        ShownPhotosPage(
            page: spots.pages[spot.id],
            describe: { Self.imageDescription(for: $0, spotName: spot.name) },
            emptyNote: "A photo shows up here once its owner posts it with the spot showing "
                + "and the votes have set its grade.",
            tryAgain: {
                Task { await spots.loadPhotos(atSpotID: spot.id) }
            }
        ) {
            about(spot)
        }
        // The photos are asked for each time the page opens, because a
        // link to an image works for a few minutes only.
        .task(id: spot.id) {
            await spots.loadPhotos(atSpotID: spot.id)
        }
    }

    // MARK: About the spot

    private func about(_ spot: Spot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(spot.summary)
                .font(.body)
                .foregroundStyle(Theme.ink)
            // When the light is good comes before how to get there, since
            // it decides when to go.
            if let pin = spot.coordinate {
                SpotLightSection(point: pin, viewBearing: spot.viewBearing)
            }
            ForEach(Self.notes(for: spot)) { note in
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeading(note.title)
                    Text(note.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                }
            }
            Button("Get directions") {
                openDirections(to: spot)
            }
            .buttonStyle(.secondary)
        }
    }

    /// The notes a spot comes with, in the order a visitor needs them. A
    /// note with nothing written is left out.
    static func notes(for spot: Spot) -> [SpotNote] {
        [
            SpotNote(title: "Getting there", text: spot.accessNotes),
            SpotNote(title: "Local rules", text: spot.localRules),
            SpotNote(title: "Runways", text: spot.runwayNotes),
        ]
        .filter { !$0.text.isEmpty }
    }

    private func openDirections(to spot: Spot) {
        guard let url = URL(string: "https://maps.apple.com/?daddr=\(spot.latitude),\(spot.longitude)&dirflg=d") else {
            return
        }
        openURL(url)
    }

    /// What VoiceOver reads for a photo on the page.
    static func imageDescription(for photo: SpotPhoto, spotName: String) -> String {
        let subject = [photo.airline, photo.aircraftType].compactMap { $0 }.joined(separator: " ")
        return subject.isEmpty ? "A photo taken from \(spotName)" : "\(subject), taken from \(spotName)"
    }
}

#Preview("A spot with photos") {
    let sync = SyncCoordinator.preview()
    NavigationStack {
        SpotPageView(spotID: "atl-south-approach")
    }
    .environment(SampleData.model())
    .environment(SpotsModel.preview(session: sync.session))
}

#Preview("A spot with no photos") {
    let sync = SyncCoordinator.preview()
    NavigationStack {
        SpotPageView(spotID: "atl-west-road")
    }
    .environment(SampleData.model())
    .environment(SpotsModel.preview(session: sync.session))
}
