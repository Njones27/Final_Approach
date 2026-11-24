import CoreLocation
import FinalApproachCore
import MapKit
import SwiftUI

/// Where a tap on the spot card leads.
enum SpotRoute: Hashable {
    /// The page of one spot, by spot id.
    case page(String)
}

/// What the card says while there is no spot to show.
private enum SpotsNotice: String {
    case loading
    case signInNeeded
    case couldNotLoad
    case noSpots
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
/// located photos on top. The selected spot or photo has a card, and a
/// spot's card shows the best graded photos people chose to show there.
///
/// The spots come from the backend, so the list changes with no release.
/// A build with no backend shows the sample spots.
///
/// Only the owner uses this screen, so their undisclosed photos are placed
/// on it too. None of the user's own pins is shown to another person.
struct SpotsView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(SpotsModel.self) private var spots
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

    /// The listed airports. The backend lists them for a signed in user,
    /// so none shows while the user needs to sign in.
    private var airports: [Airport] {
        spots.phase == .signInNeeded ? [] : model.airports
    }

    /// The chosen airport, or the first one until the user picks.
    private var airport: Airport? {
        airports.first { $0.id == airportID } ?? airports.first
    }

    /// The first spot at this airport, which has the card until the user
    /// picks. The list is curated, so its order is the order to show.
    private var firstSpot: Spot? {
        airport?.spots.first
    }

    /// What the card says while no airport is listed, or nil when one is.
    private var notice: SpotsNotice? {
        guard airports.isEmpty else { return nil }
        switch spots.phase {
        case .idle, .loading: return .loading
        case .signInNeeded: return .signInNeeded
        case .couldNotLoad: return .couldNotLoad
        case .loaded: return .noSpots
        }
    }

    /// True when the spot on the card has no photos in hand, not even a
    /// request for them. They are asked for then.
    private var selectedSpotNeedsPhotos: Bool {
        guard let selectedSpot else { return false }
        return spots.pages[selectedSpot.id] == nil
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
            return airport?.spots.first { $0.id == id } ?? firstSpot
        case .some(.photo):
            // A selected photo that has since been deleted gives the card
            // back to the first spot.
            return selectedPhoto == nil ? firstSpot : nil
        case .none:
            return firstSpot
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
        if let notice { return "notice:\(notice.rawValue)" }
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
                    // A photo pin stands above its place, so it does not cover
                    // the pin of the spot it was taken from.
                    Annotation(place.photo.typeTitle, coordinate: place.coordinate, anchor: .bottom) {
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
            // The map fills the screen, so it fades in and stays put. The
            // card over it slides in as the other tabs' content does.
            .arrivesWithTab(travels: false)
            .background(Theme.ground)
            .safeAreaInset(edge: .bottom) {
                card
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .animation(Motion.swap, value: cardID)
                    .arrivesWithTab()
            }
            .sensoryFeedback(.selection, trigger: selection)
            .navigationTitle("Spots")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                mapActions
            }
            .navigationDestination(for: SpotRoute.self) { route in
                switch route {
                case let .page(spotID):
                    SpotPageView(spotID: spotID)
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
            // The spots arrive from the backend after the screen opens, and
            // the user can pick another airport. Either way the map moves
            // to the airport's spots.
            .onChange(of: airport?.id) {
                frameAirport(animated: true)
            }
            // The list is asked for each time the screen comes back and
            // when the sign in changes, so a spot added on the backend
            // shows up with no release.
            .task(id: spots.session.state) {
                await spots.refresh(on: model)
            }
            // The photos are asked for each time a spot takes the card and
            // each time the screen comes back, because a link to an image
            // works for a few minutes only.
            .task(id: selectedSpot?.id) {
                guard let id = selectedSpot?.id else { return }
                await spots.loadPhotos(atSpotID: id)
            }
            // The photos in hand are dropped when the user deletes one of
            // their own, so they are asked for again.
            .onChange(of: selectedSpotNeedsPhotos) { _, needsPhotos in
                guard needsPhotos, let id = selectedSpot?.id else { return }
                Task { await spots.loadPhotos(atSpotID: id) }
            }
        }
    }

    /// The card under the map. One of the user's photos has it when one is
    /// selected, and otherwise a spot does. While no spot is listed it
    /// says why.
    private var card: some View {
        ZStack(alignment: .bottom) {
            if let photo = selectedPhoto {
                OwnPhotoCard(
                    photo: photo,
                    image: model.image(for: photo),
                    spotName: model.listedSpot(for: photo)?.name,
                    zoomNamespace: photoZoom
                )
                .transition(.opacity)
            } else if let spot = selectedSpot {
                SpotCard(spot: spot, page: spots.pages[spot.id]) {
                    openDirections(to: spot)
                }
                .transition(.opacity)
            } else if let notice {
                NoticeCard(notice: notice) {
                    Task { await spots.refresh(on: model) }
                }
                .transition(.opacity)
            }
        }
    }

    @ToolbarContentBuilder
    private var mapActions: some ToolbarContent {
        if !airports.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                airportMenu
            }
        } else if !ownPhotoPlaces.isEmpty {
            // With no airport to pick, the menu would hold one action, so
            // the action stands alone.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Your photos", systemImage: "photo.on.rectangle") {
                    showOwnPhotos()
                }
            }
        }
    }

    private var airportMenu: some View {
        Menu(airport?.displayName ?? "Airport") {
            Picker("Airport", selection: airportSelection) {
                ForEach(airports) { airport in
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

    /// Reads the airport on screen and, on a change, clears the selection.
    /// The map then moves to the new airport's spots.
    private var airportSelection: Binding<String> {
        Binding(
            get: { airport?.id ?? "" },
            set: { newID in
                airportID = newID
                selection = nil
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

/// A round pin that marks a listed spot.
private struct SpotPin: View {
    let spot: Spot
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Image(systemName: "binoculars.fill")
                .font(isSelected ? .body : .subheadline)
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
        .accessibilityLabel(spot.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small square of one of the user's own photos, with a pointer down to
/// where it was taken. The square stands clear of that place, because a
/// photo is often taken at a listed spot and would cover the spot's pin.
private struct PhotoPin: View {
    let image: Image
    let description: String
    let isSelected: Bool
    let select: () -> Void

    /// The room left between the pointer and the place, which clears a
    /// selected spot pin.
    private static let clearance: CGFloat = 28

    var body: some View {
        VStack(spacing: -2) {
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

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .padding(.bottom, Self.clearance)
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
            // changes. Only the picture and words fade to the new one. The
            // card is laid out as the spot card is, with the same heights,
            // so the map under it holds still when one card takes the
            // other's place.
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.typeTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(placeText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2, reservesSpace: true)
                }
                PhotoFill(image: image, description: photo.imageDescription)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .matchedTransitionSource(id: ZoomSource.mapCard(photo.id), in: zoomNamespace)
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

/// The card for the selected spot, with its best photos and two actions.
private struct SpotCard: View {
    let spot: Spot
    /// The spot's photos as far as they are known, or nil before they were
    /// asked for.
    let page: SpotsModel.Page?
    let getDirections: () -> Void

    /// How many photos the card has room for.
    private static let stripCount = 3

    /// The best photos, which the card shows.
    private var bestPhotos: [SpotPhoto] {
        Array((page?.photos ?? []).prefix(Self.stripCount))
    }

    /// What stands in for the photos while there are none to show.
    private var stripNote: String {
        switch page?.phase {
        case .loaded?: "No graded photos here yet"
        case .couldNotLoad?: "The photos could not be loaded"
        case .loading?, nil: "Finding photos"
        }
    }

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
                // The strip keeps its height with or without photos, for
                // the same reason.
                strip
                    .frame(height: 70)
            }
            .id(spot.id)
            .transition(.fadeThrough)

            HStack(spacing: 8) {
                Button("Get directions", action: getDirections)
                    .buttonStyle(.primaryCompact)
                NavigationLink(value: SpotRoute.page(spot.id)) {
                    Text("Open spot")
                }
                .buttonStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.scrim.opacity(0.25), radius: 17, y: 12)
    }

    @ViewBuilder
    private var strip: some View {
        if bestPhotos.isEmpty {
            Text(stripNote)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            HStack(spacing: 6) {
                ForEach(bestPhotos) { photo in
                    SpotThumbnail(photo: photo, description: "A photo taken from \(spot.name)")
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

/// The card that stands in for a spot while none is listed. It says why,
/// and offers another try when the spots could not be loaded.
private struct NoticeCard: View {
    let notice: SpotsNotice
    let tryAgain: () -> Void

    private var title: String {
        switch notice {
        case .loading: "Finding spots"
        case .signInNeeded: "Sign in to see the spots"
        case .couldNotLoad: "The spots could not be loaded"
        case .noSpots: "No spots are listed yet"
        }
    }

    private var detail: String {
        switch notice {
        case .loading:
            "The list of spots is on its way."
        case .signInNeeded:
            "Sign in on Profile to see the spots and the photos people chose to show there."
        case .couldNotLoad:
            "Check your connection and try again."
        case .noSpots:
            "Spots are added by hand, with how to get there and the local rules. Your own photos are on the map."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(notice)
            .transition(.fadeThrough)

            if notice == .couldNotLoad {
                Button("Try again", action: tryAgain)
                    .buttonStyle(.primaryCompact)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.scrim.opacity(0.25), radius: 17, y: 12)
    }
}

#Preview("Sample spots") {
    let sync = SyncCoordinator.preview()
    SpotsView()
        .environment(SampleData.model())
        .environment(SpotsModel.preview(session: sync.session))
}

#Preview("No spots listed") {
    let sync = SyncCoordinator.preview()
    SpotsView()
        .environment(SampleData.model(airports: []))
        .environment(SpotsModel.preview(session: sync.session, backend: SampleSpotBackend(airports: [])))
}

#Preview("Signed out") {
    let sync = SyncCoordinator.preview(.signedOut)
    SpotsView()
        .environment(SampleData.model(airports: []))
        .environment(SpotsModel.preview(session: sync.session, needsSignIn: true))
}
