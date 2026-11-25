import FinalApproachCore
import SwiftUI

/// One note about a spot, such as how to get there.
struct SpotNote: Identifiable, Equatable {
    let title: String
    let text: String

    var id: String { title }
}

/// The page of one spot. It says how to get there and what the place asks
/// of a visitor, and shows the best graded photos people chose to show
/// from it.
///
/// A photo here is another person's. It comes with its grade, its tier,
/// and the aircraft type and airline its owner chose to show. There is no
/// photographer and no registration, and a photo whose owner kept the
/// location private never appears.
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                about(spot)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 20)
                photosHeading
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                photos(spots.pages[spot.id], at: spot)
            }
            .padding(.bottom, 32)
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

    // MARK: The photos

    private var photosHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading("Photos from here")
            Text("The best graded photos people chose to show at this spot. Names and registrations stay hidden.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private func photos(_ page: SpotsModel.Page?, at spot: Spot) -> some View {
        let shown = page?.photos ?? []
        if shown.isEmpty {
            switch page?.phase {
            case .loaded?:
                ContentUnavailableView(
                    "No graded photos here yet",
                    systemImage: "photo.on.rectangle",
                    description: Text(
                        "A photo shows up here once its owner posts it with the spot showing and the votes have set its grade."
                    )
                )
                .padding(.top, 12)
            case .couldNotLoad?:
                ContentUnavailableView {
                    Label("The photos could not be loaded", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") {
                        Task { await spots.loadPhotos(atSpotID: spot.id) }
                    }
                }
                .padding(.top, 12)
            case .loading?, nil:
                ProgressView("Finding photos")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        } else {
            ForEach(shown) { photo in
                SpotPhotoRow(
                    photo: photo,
                    tier: model.thresholds.tier(forScore: Double(photo.score)),
                    spotName: spot.name
                )
            }
        }
    }

    /// What VoiceOver reads for a photo on the page.
    static func imageDescription(for photo: SpotPhoto, spotName: String) -> String {
        let subject = [photo.airline, photo.aircraftType].compactMap { $0 }.joined(separator: " ")
        return subject.isEmpty ? "A photo taken from \(spotName)" : "\(subject), taken from \(spotName)"
    }
}

/// One photo on a spot's page, with what its owner chose to show and the
/// grade the votes gave it.
private struct SpotPhotoRow: View {
    let photo: SpotPhoto
    let tier: Tier
    let spotName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpotThumbnail(
                photo: photo,
                description: SpotPageView.imageDescription(for: photo, spotName: spotName)
            )
            .aspectRatio(3 / 2, contentMode: .fit)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    // A photo with no aircraft type has its owner's reason
                    // for it, so the page does not guess one.
                    Text(photo.aircraftType ?? "Aircraft not named")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if let airline = photo.airline {
                        Text(airline)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Double(photo.score).scoreText)
                        .font(.condensed(30, relativeTo: .title2))
                        .foregroundStyle(Theme.ink)
                    TierLabel(tier: tier, font: .footnote.weight(.semibold))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Grade \(photo.score), \(tier.displayName)")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
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
