import FinalApproachCore
import SwiftUI

/// The body of a spot's or a place's page. It opens on the top voted photo
/// shown there, then says what the page has to say about the spot or the
/// place, and then shows the rest of the photos, best first.
///
/// A photo here is another person's. It comes with its grade, its tier,
/// and the aircraft type, airline, and camera settings its owner chose to
/// show. There is no photographer and no registration.
struct ShownPhotosPage<About: View>: View {
    /// The photos as far as they are known, or nil before they were asked
    /// for.
    let page: SpotsModel.Page?
    /// What VoiceOver reads for a photo.
    let describe: (SpotPhoto) -> String
    /// What the page says once it is known that no photo is shown here.
    let emptyNote: String
    let tryAgain: () -> Void
    private let about: About

    @Environment(CollectionModel.self) private var model

    init(
        page: SpotsModel.Page?,
        describe: @escaping (SpotPhoto) -> String,
        emptyNote: String,
        tryAgain: @escaping () -> Void,
        @ViewBuilder about: () -> About
    ) {
        self.page = page
        self.describe = describe
        self.emptyNote = emptyNote
        self.tryAgain = tryAgain
        self.about = about()
    }

    private var photos: [SpotPhoto] {
        page?.photos ?? []
    }

    /// True while the photos are on their way and none is in hand.
    private var isFinding: Bool {
        photos.isEmpty && (page == nil || page?.phase == .loading)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                top
                about
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 20)
                heading
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                rest
            }
            .padding(.bottom, 32)
        }
    }

    private func tier(for photo: SpotPhoto) -> Tier {
        model.thresholds.tier(forScore: Double(photo.score))
    }

    /// The top voted photo, which the page opens on. Its room is held
    /// while the photos are on their way, so the page does not jump when
    /// they arrive.
    @ViewBuilder
    private var top: some View {
        if let best = photos.first {
            ShownPhotoRow(photo: best, tier: tier(for: best), description: describe(best), note: "Top voted here")
        } else if isFinding {
            Theme.controlFill
                .aspectRatio(3 / 2, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading(photos.count > 1 ? "More photos from here" : "Photos from here")
            Text("The best graded photos people chose to show here. Names and registrations stay hidden.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// The photos after the top one, or why there is none.
    @ViewBuilder
    private var rest: some View {
        if photos.count > 1 {
            ForEach(Array(photos.dropFirst())) { photo in
                ShownPhotoRow(photo: photo, tier: tier(for: photo), description: describe(photo))
            }
        } else if photos.count == 1 {
            Text("The photo above is the only graded one shown here so far.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 20)
        } else {
            switch page?.phase {
            case .loaded?:
                ContentUnavailableView(
                    "No graded photos here yet",
                    systemImage: "photo.on.rectangle",
                    description: Text(emptyNote)
                )
                .padding(.top, 12)
            case .couldNotLoad?:
                ContentUnavailableView {
                    Label("The photos could not be loaded", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again", action: tryAgain)
                }
                .padding(.top, 12)
            case .loading?, nil:
                ProgressView("Finding photos")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }
}

/// One photo on a spot's or a place's page, with what its owner chose to
/// show and the grade the votes gave it.
struct ShownPhotoRow: View {
    let photo: SpotPhoto
    let tier: Tier
    /// What the photo shows, read by VoiceOver.
    let description: String
    /// A word about the photo's standing on the page, such as that it is
    /// the top voted one.
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpotThumbnail(photo: photo, description: description)
                .aspectRatio(3 / 2, contentMode: .fit)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let note {
                        Text(note)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
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
                    // How the photo was taken, so a visitor can see what
                    // lens the place needs. The camera and lens are never
                    // named.
                    if let settings = photo.camera?.summary {
                        Label(settings, systemImage: "camera")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 4)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Taken at \(settings)")
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
