import CoreLocation
import MapKit
import SwiftUI

/// Where a tap on the spot card leads.
enum SpotRoute: Hashable {
    case photos(String)
}

/// A map of the curated spots around one airport. Each pin shows how many
/// photos were shared from that spot, and the selected spot has a card.
struct SpotsView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var airportID: String?
    @State private var selectedSpotID: String?
    @State private var position = MapCameraPosition.automatic

    /// The chosen airport, or the first one until the user picks.
    private var airport: Airport? {
        model.airports.first { $0.id == airportID } ?? model.airports.first
    }

    /// The chosen spot, or the busiest one at this airport until the user
    /// picks.
    private var selectedSpot: Spot? {
        guard let airport else { return nil }
        return airport.spots.first { $0.id == selectedSpotID }
            ?? airport.spots.max { $0.photoCount < $1.photoCount }
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
                                selectedSpotID = spot.id
                            }
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .safeAreaInset(edge: .bottom) {
                ZStack(alignment: .bottom) {
                    if let spot = selectedSpot {
                        SpotCard(spot: spot) {
                            openDirections(to: spot)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
                .animation(Motion.swap, value: selectedSpot?.id)
            }
            .sensoryFeedback(.selection, trigger: selectedSpotID)
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
        }
    }

    private var airportMenu: some View {
        Menu(airport?.displayName ?? "Airport") {
            Picker("Airport", selection: airportSelection) {
                ForEach(model.airports) { airport in
                    Text(airport.displayName).tag(airport.id)
                }
            }
        }
    }

    /// Reads the airport on screen and, on a change, clears the selected
    /// spot and frames the new airport's spots.
    private var airportSelection: Binding<String> {
        Binding(
            get: { airport?.id ?? "" },
            set: { newID in
                airportID = newID
                selectedSpotID = nil
                withAnimation(Motion.swap) {
                    position = .automatic
                }
            }
        )
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
