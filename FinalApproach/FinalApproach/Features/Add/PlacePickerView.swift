import CoreLocation
import FinalApproachCore
import MapKit
import SwiftUI

/// Lets the user say where a photo was taken.
///
/// A pin stays in the middle of the map and the map moves under it, so the
/// place under the pin is the answer. The listed spots are marked, and
/// tapping one moves the pin onto it. A search moves the map to an airport
/// or any other place by name, so a photo can be placed anywhere and not
/// only at a listed spot.
struct PlacePickerView: View {
    /// Where the map opens. With none, it frames the first listed airport.
    let start: Coordinate?
    /// True when the photo already has a pin, which adds a way to remove it.
    let hasPin: Bool
    /// Called with the chosen place, or with nil when the pin is removed.
    let choose: (Coordinate?) -> Void

    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = MapCameraPosition.automatic
    @State private var hasFramedMap = false
    /// The place under the pin, once the map has settled.
    @State private var pinPlace: Coordinate?
    /// Where the map draws its own center, in the map's own space.
    @State private var pinPoint: CGPoint?
    @State private var mapSize = CGSize.zero
    @State private var searchText = ""
    @State private var searchNotice: String?

    /// How far above the ground the map opens on one place, in meters.
    private static let placeDistance: CLLocationDistance = 4_000
    /// How far above the ground the map shows a searched place, in meters.
    /// It is higher, since a search often names a whole airport.
    private static let searchDistance: CLLocationDistance = 12_000
    /// How much room to leave around the listed spots, as a share of their
    /// spread, and the smallest area to frame, in degrees.
    private static let framePadding = 0.3
    private static let minimumFrameSpan = 0.02
    /// The height of the pin, whose tip marks the place.
    private static let pinHeight: CGFloat = 40

    private var spots: [Spot] {
        model.airports.flatMap(\.spots)
    }

    /// The listed spot the pin is on or near, when there is one.
    private var nearestSpot: Spot? {
        pinPlace.flatMap { model.nearestSpot(to: $0) }
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                // The bar sits under the map and not over it, so the middle
                // of the map is the middle of what the user can see.
                VStack(spacing: 0) {
                    map(read: proxy)
                    confirmBar(read: proxy)
                }
            }
            .background(Theme.ground)
            .navigationTitle("Where was this taken?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search for an airport or a place")
            .onSubmit(of: .search) {
                Task {
                    await search()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if hasPin {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Remove pin", role: .destructive) {
                            choose(nil)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                guard !hasFramedMap else { return }
                hasFramedMap = true
                frameOpeningView()
            }
        }
    }

    private func map(read proxy: MapProxy) -> some View {
        Map(position: $position) {
            ForEach(spots) { spot in
                Annotation(
                    spot.name,
                    coordinate: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                    anchor: .center
                ) {
                    SpotDot(name: spot.name) {
                        if let coordinate = spot.coordinate {
                            move(to: coordinate, distance: Self.placeDistance)
                        }
                    }
                }
            }
        }
        // Airports stay on the map, since most photos are taken at one.
        .mapStyle(.standard(pointsOfInterest: .including([.airport])))
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { size in
            mapSize = size
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            let center = context.camera.centerCoordinate
            pinPlace = Coordinate(latitude: center.latitude, longitude: center.longitude)
            // The map says where on screen its own center is, and the pin
            // is drawn there, so the two cannot drift apart.
            pinPoint = proxy.convert(center, to: .local)
        }
        .overlay(alignment: .topLeading) {
            let point = pinPoint ?? CGPoint(x: mapSize.width / 2, y: mapSize.height / 2)
            Image(systemName: "mappin")
                .font(.system(size: Self.pinHeight, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .shadow(color: Theme.ground.opacity(0.6), radius: 2)
                .frame(height: Self.pinHeight)
                // The pin's tip, at the bottom of the image, marks the place.
                .position(x: point.x, y: point.y - Self.pinHeight / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// What the pin is on, and the button that uses it.
    private func confirmBar(read proxy: MapProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nearestSpot.map { "Near \($0.name)" } ?? "Move the map to put the pin where you stood.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                if let searchNotice {
                    Text(searchNotice)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Use this place") {
                if let place = pinPlace ?? place(underPinIn: proxy) {
                    choose(place)
                }
                dismiss()
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.ground)
    }

    // MARK: Map

    /// The place under the pin, asked of the map directly. It covers a tap
    /// on the button before the map has reported where it settled.
    private func place(underPinIn proxy: MapProxy) -> Coordinate? {
        guard mapSize != .zero else { return nil }
        let point = pinPoint ?? CGPoint(x: mapSize.width / 2, y: mapSize.height / 2)
        guard let found = proxy.convert(point, from: .local) else { return nil }
        return Coordinate(latitude: found.latitude, longitude: found.longitude)
    }

    /// Opens on the given place, or on the spots of the first listed
    /// airport when there is none.
    private func frameOpeningView() {
        if let start {
            position = .camera(camera(over: start, distance: Self.placeDistance))
            return
        }
        let firstSpots = model.airports.first?.spots ?? []
        guard let bounds = GeoBounds(points: firstSpots.compactMap(\.coordinate)) else { return }
        let spans = bounds.framedSpans(padding: Self.framePadding, minimumSpan: Self.minimumFrameSpan)
        position = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: bounds.center.latitude, longitude: bounds.center.longitude),
                span: MKCoordinateSpan(latitudeDelta: spans.latitude, longitudeDelta: spans.longitude)
            )
        )
    }

    private func camera(over place: Coordinate, distance: CLLocationDistance) -> MapCamera {
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            distance: distance
        )
    }

    /// Moves the map so the pin is over a place. With Reduce Motion on, the
    /// map jumps there.
    private func move(to place: Coordinate, distance: CLLocationDistance) {
        withAnimation(reduceMotion ? nil : Motion.swap) {
            position = .camera(camera(over: place, distance: distance))
        }
    }

    // MARK: Search

    /// Moves the map to the first place Apple Maps finds for the search.
    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            let found = response.mapItems.first?.location.coordinate
            guard let found, let place = Coordinate(latitude: found.latitude, longitude: found.longitude) else {
                searchNotice = "No place was found for that search."
                return
            }
            searchNotice = nil
            move(to: place, distance: Self.searchDistance)
        } catch {
            searchNotice = "The search did not work. Check your connection and try again."
        }
    }
}

/// A small mark for a listed spot. Tapping it moves the pin onto the spot.
private struct SpotDot: View {
    let name: String
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Circle()
                .fill(Theme.surface)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().strokeBorder(Theme.ink, lineWidth: 2)
                }
                // The mark is small, so the area that takes a tap is larger.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityHint("Moves the pin to this spot")
    }
}

#Preview("No pin yet") {
    PlacePickerView(start: nil, hasPin: false) { _ in }
        .environment(SampleData.model())
}

#Preview("Moving a pin") {
    PlacePickerView(start: SampleData.model().airports.first?.spots.first?.coordinate, hasPin: true) { _ in }
        .environment(SampleData.model())
}
