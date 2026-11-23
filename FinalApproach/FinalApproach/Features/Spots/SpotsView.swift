import CoreLocation
import FinalApproachCore
import MapKit
import SwiftUI

/// Where a tap on the spot card leads.
enum SpotRoute: Hashable {
    case photos(String)
}

/// What the card under the map is about.
private enum MapSelection: Equatable {
    case spot(String)
    /// One of the user's own photos.
    case photo(String)
}

/// One of the user's own photos placed on the map.
private struct OwnPhotoPlace: Identifiable {
    let photo: SpottedPhoto
    let coordinate: CLLocationCoordinate2D

    var id: String { photo.id }
}

/// A map of the curated spots around one airport, with the user's own
/// located photos on top. Each spot pin shows how many photos were shared
/// from that spot, and the selected spot or photo has a card.
///
/// Only the owner uses this screen, so their undisclosed photos are placed
/// on it too. Nothing here is shown to another person.
struct SpotsView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Namespace private var photoZoom
    @State private var airportID: String?
    @State private var selection: MapSelection?
    @State private var position = MapCameraPosition.automatic
    @State private var hasFramedMap = false

    /// How much room to leave around the framed places, as a share of
    /// their spread.
    private static let framePadding = 0.6
    /// The smallest area the map frames, in degrees, so one place alone is
    /// not shown from street level.
    private static let minimumFrameSpan = 0.02

    /// The chosen airport, or the first one until the user picks.
    private var airport: Airport? {
        model.airports.first { $0.id == airportID } ?? model.airports.first
    }

    /// The busiest spot at this airport, which has the card until the user
    /// picks.
    private var busiestSpot: Spot? {
        airport?.spots.max { $0.photoCount < $1.photoCount }
    }

    /// The user's photo whose card is showing, when one is selected and it
    /// is still in the collection.
    private var selectedPhoto: SpottedPhoto? {
        guard case let .photo(id) = selection else { return nil }
        return model.photo(id: id)
    }

    /// The spot whose card is showing. It is nil while one of the user's
    /// photos has the card.
    private var selectedSpot: Spot? {
        switch selection {
        case let .some(.spot(id)):
            return airport?.spots.first { $0.id == id } ?? busiestSpot
        case .some(.photo):
            // A selected photo that has since been deleted gives the card
            // back to the busiest spot.
            return selectedPhoto == nil ? busiestSpot : nil
        case .none:
            return busiestSpot
        }
    }

    /// The user's photos that carry a location, as places on the map.
    private var ownPhotoPlaces: [OwnPhotoPlace] {
        model.locatedPhotos.compactMap { photo in
            guard let coordinate = photo.ownerCaptureCoordinate else { return nil }
            return OwnPhotoPlace(photo: photo, coordinate: mapCoordinate(coordinate))
        }
    }

    /// What the card shows, so it can fade when that changes.
    private var cardID: String {
        if let selectedPhoto { return "photo:\(selectedPhoto.id)" }
        if let selectedSpot { return "spot:\(selectedSpot.id)" }
        return ""
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(airport?.spots ?? []) { spot in
                    Annotation(
                        spot.name,
                        coordinate: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                        anchor: .center
                    ) {
                        SpotPin(spot: spot, isSelected: spot.id == selectedSpot?.id) {
                            withAnimation(Motion.swap) {
                                selection = .spot(spot.id)
                            }
                        }
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(ownPhotoPlaces) { place in
                    Annotation(place.photo.aircraftType, coordinate: place.coordinate, anchor: .center) {
                        PhotoPin(
                            image: model.image(for: place.photo),
                            description: place.photo.imageDescription,
                            isSelected: place.id == selectedPhoto?.id
                        ) {
                            withAnimation(Motion.swap) {
                                selection = .photo(place.id)
                            }
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .safeAreaInset(edge: .bottom) {
                ZStack(alignment: .bottom) {
                    if let photo = selectedPhoto {
                        OwnPhotoCard(
                            photo: photo,
                            image: model.image(for: photo),
                            spotName: photo.spotID.flatMap { model.spot(id: $0)?.name },
                            zoomNamespace: photoZoom
                        )
                        .transition(.opacity)
                    } else if let spot = selectedSpot {
                        SpotCard(spot: spot) {
                            openDirections(to: spot)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .animation(Motion.swap, value: cardID)
            }
            .sensoryFeedback(.selection, trigger: selection)
            .navigationTitle("Spots")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    airportMenu
                }
            }
            .navigationDestination(for: SpotRoute.self) { route in
                switch route {
                case let .photos(spotID):
                    SpotPhotosView(spotID: spotID)
                }
            }
            .photoDestinations(zoomingIn: photoZoom)
            .onAppear {
                // The map opens on the airport's spots. Framing them by hand
                // keeps a photo taken far away from pulling the view out.
                guard !hasFramedMap else { return }
                hasFramedMap = true
                frameAirport(animated: false)
            }
        }
    }

    private var airportMenu: some View {
        Menu(airport?.displayName ?? "Airport") {
            Picker("Airport", selection: airportSelection) {
                ForEach(model.airports) { airport in
                    Text(airport.displayName).tag(airport.id)
                }
            }
            if !ownPhotoPlaces.isEmpty {
                Button("Your photos", systemImage: "photo.on.rectangle") {
                    showOwnPhotos()
                }
            }
        }
    }

    /// Reads the airport on screen and, on a change, clears the selection
    /// and frames the new airport's spots.
    private var airportSelection: Binding<String> {
        Binding(
            get: { airport?.id ?? "" },
            set: { newID in
                airportID = newID
                selection = nil
                frameAirport(animated: true)
            }
        )
    }

    // MARK: Framing

    private func mapCoordinate(_ coordinate: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// Moves the map so every point is in view with room around it.
    private func showOnMap(_ points: [Coordinate], animated: Bool) {
        guard let bounds = GeoBounds(points: points) else { return }
        let spans = bounds.framedSpans(padding: Self.framePadding, minimumSpan: Self.minimumFrameSpan)
        let region = MKCoordinateRegion(
            center: mapCoordinate(bounds.center),
            span: MKCoordinateSpan(latitudeDelta: spans.latitude, longitudeDelta: spans.longitude)
        )
        if animated {
            withAnimation(Motion.swap) {
                position = .region(region)
            }
        } else {
            position = .region(region)
        }
    }

    private func frameAirport(animated: Bool) {
        showOnMap((airport?.spots ?? []).compactMap(\.coordinate), animated: animated)
    }

    /// Frames every one of the user's located photos and gives the newest
    /// one the card.
    private func showOwnPhotos() {
        let places = ownPhotoPlaces
        guard let newest = places.first else { return }
        showOnMap(places.compactMap(\.photo.ownerCaptureCoordinate), animated: true)
        withAnimation(Motion.swap) {
            selection = .photo(newest.id)
        }
    }

    private func openDirections(to spot: Spot) {
        guard let url = URL(string: "https://maps.apple.com/?daddr=\(spot.latitude),\(spot.longitude)&dirflg=d") else {
            return
        }
        openURL(url)
    }
}

/// A round pin with the spot's photo count.
private struct SpotPin: View {
    let spot: Spot
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Text("\(spot.photoCount)")
                .font(.condensed(isSelected ? 20 : 18, relativeTo: .body))
                .foregroundStyle(isSelected ? Theme.ground : Theme.ink)
                .frame(width: isSelected ? 52 : 44, height: isSelected ? 52 : 44)
                .background(isSelected ? Theme.ink : Theme.surface, in: Circle())
                .overlay {
                    Circle().strokeBorder(Theme.ink.opacity(isSelected ? 0 : 0.4), lineWidth: 1)
                }
                .padding(isSelected ? 8 : 0)
                .background(Theme.ink.opacity(isSelected ? 0.2 : 0), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(spot.name), \(spot.photoCount) photos")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small square of one of the user's own photos, placed where it was
/// taken.
private struct PhotoPin: View {
    let image: Image
    let description: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            PhotoFill(image: image, description: description)
                .frame(width: isSelected ? 52 : 40, height: isSelected ? 52 : 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: isSelected ? 3 : 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your photo, \(description)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The card for one of the user's own photos on the map. It says which
/// listed spot the photo was taken near and opens the photo.
private struct OwnPhotoCard: View {
    let photo: SpottedPhoto
    let image: Image
    /// The name of the spot the photo is linked to, when there is one.
    let spotName: String?
    let zoomNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The card and its button stay where they are when the photo
            // changes. Only the picture and words fade to the new one.
            HStack(alignment: .center, spacing: 12) {
                PhotoFill(image: image, description: photo.imageDescription)
                    .frame(width: 96, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .matchedTransitionSource(id: ZoomSource.mapCard(photo.id), in: zoomNamespace)
                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.aircraftType)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(placeText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2, reservesSpace: true)
                }
                Spacer(minLength: 0)
            }
            .id(photo.id)
            .transition(.fadeThrough)

            NavigationLink(value: PhotoRoute.photo(id: photo.id, source: .mapCard(photo.id))) {
                Text("Open your photo")
            }
            .buttonStyle(.primaryCompact)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.scrim.opacity(0.25), radius: 17, y: 12)
    }

    private var placeText: String {
        let place = spotName.map { "Taken near \($0)." } ?? "Taken away from the listed spots."
        return photo.isLocationUndisclosed ? "\(place) Only you can see this." : place
    }
}

/// The card for the selected spot, with a few photos and two actions.
private struct SpotCard: View {
    let spot: Spot
    let getDirections: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The card and its buttons stay where they are when the spot
            // changes. Only the words and photos fade to the new spot.
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(spot.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        // Room for two lines is always kept, so the card
                        // and the map under it hold still between spots.
                        .lineLimit(2, reservesSpace: true)
                }
                HStack(spacing: 6) {
                    ForEach(spot.photoNames, id: \.self) { name in
                        PhotoFill(imageName: name, description: "A photo taken from \(spot.name)")
                            .frame(height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .id(spot.id)
            .transition(.fadeThrough)

            HStack(spacing: 8) {
                Button("Get directions", action: getDirections)
                    .buttonStyle(.primaryCompact)
                NavigationLink(value: SpotRoute.photos(spot.id)) {
                    Text("See all \(spot.photoCount) photos")
                        .contentTransition(.numericText())
                }
                .buttonStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.scrim.opacity(0.25), radius: 17, y: 12)
    }
}

#Preview {
    SpotsView()
        .environment(SampleData.model())
}
