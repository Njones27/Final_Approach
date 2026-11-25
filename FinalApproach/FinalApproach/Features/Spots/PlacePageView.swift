import FinalApproachCore
import SwiftUI

/// The page of one place, which is a cell of the map about a hundred
/// meters across that people chose to show photos from. It opens on the
/// top voted photo and shows the rest with how each was taken.
///
/// A place has no name, notes, or directions, because no one has checked
/// it the way a listed spot is checked. All that is known about where its
/// photos were taken is the middle of its cell.
struct PlacePageView: View {
    let placeID: String

    @Environment(CollectionModel.self) private var model
    @Environment(SpotsModel.self) private var spots

    var body: some View {
        ShownPhotosPage(
            page: spots.placePages[placeID],
            describe: { Self.imageDescription(for: $0) },
            emptyNote: "A photo shows up here once its owner posts it with its location showing "
                + "and the votes have set its grade.",
            tryAgain: {
                Task { await spots.loadPhotos(atPlaceID: placeID) }
            }
        ) {
            about
        }
        .background(Theme.ground)
        .navigationTitle("Unnamed place")
        .navigationBarTitleDisplayMode(.inline)
        // The photos are asked for each time the page opens, because a
        // link to an image works for a few minutes only.
        .task(id: placeID) {
            await spots.loadPhotos(atPlaceID: placeID)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Self.aboutText(meters: model.placeGrid.roughCellMeters))
                .font(.body)
                .foregroundStyle(Theme.ink)
            // A place does not say which way it looks, so the light is
            // golden hour only.
            if let middle = model.placeGrid.center(ofPlaceID: placeID) {
                SpotLightSection(point: middle, viewBearing: nil)
            }
        }
    }

    /// What the page says about a place.
    static func aboutText(meters: Int) -> String {
        "People chose to show photos from this place, which the map marks to about \(meters) meters. "
            + "It has no name, notes, or directions, because no one has checked it the way a listed spot is checked."
    }

    /// What VoiceOver reads for a photo on the page.
    static func imageDescription(for photo: SpotPhoto) -> String {
        let subject = [photo.airline, photo.aircraftType].compactMap { $0 }.joined(separator: " ")
        return subject.isEmpty ? "A photo taken from this place" : "\(subject), taken from this place"
    }
}

/// A place's page on the sample places, for the preview. The place is the
/// first one near the first sample airport.
private struct PlacePagePreview: View {
    @Environment(CollectionModel.self) private var model
    @Environment(SpotsModel.self) private var spots

    var body: some View {
        NavigationStack {
            if let place = spots.around?.shown.places.first {
                PlacePageView(placeID: place.id)
            } else {
                ProgressView()
            }
        }
        .task {
            guard let airport = model.airports.first,
                  let middle = Coordinate(latitude: airport.latitude, longitude: airport.longitude)
            else { return }
            await spots.loadShown(around: middle)
        }
    }
}

#Preview("A place with photos") {
    let sync = SyncCoordinator.preview()
    PlacePagePreview()
        .environment(SampleData.model())
        .environment(SpotsModel.preview(session: sync.session))
}
