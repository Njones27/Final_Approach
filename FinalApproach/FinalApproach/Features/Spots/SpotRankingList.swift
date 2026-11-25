import FinalApproachCore
import SwiftUI

/// One row of the ranked list, which is a listed spot or a place.
struct RankedRow: Identifiable, Equatable {
    /// What a row stands for, and what a tap on it selects on the map.
    enum Target: Hashable {
        /// A listed spot, by spot id.
        case spot(String)
        /// A place, by place id.
        case place(String)
    }

    let target: Target
    /// The spot's name. A place has none.
    let name: String?
    /// How many graded photos are shown there.
    let photoCount: Int
    /// The photo the votes graded highest there.
    let bestPhoto: SpotPhoto

    var id: Target { target }

    /// What the row is called. A place has no name, because no one has
    /// checked it the way a listed spot is checked.
    var title: String {
        name ?? "Unnamed place"
    }

    /// How many photos are shown there, in words.
    var countText: String {
        Self.countText(photoCount)
    }

    static func countText(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count) photos"
    }

    /// The rows of the ranked list for what is shown around a point, in
    /// the order the list shows them. The order comes from `ShownRanking`.
    ///
    /// A spot that is not in `spots` is left out. It is no longer listed,
    /// so it has no name and no pin to go to.
    static func rows(for shown: ShownAround, spots: [Spot]) -> [RankedRow] {
        var rows: [String: RankedRow] = [:]
        for shownSpot in shown.spots {
            guard let listed = spots.first(where: { $0.id == shownSpot.id }) else { continue }
            rows["spot:\(shownSpot.id)"] = RankedRow(
                target: .spot(shownSpot.id),
                name: listed.name,
                photoCount: shownSpot.photoCount,
                bestPhoto: shownSpot.bestPhoto
            )
        }
        for place in shown.places {
            rows["place:\(place.id)"] = RankedRow(
                target: .place(place.id),
                name: nil,
                photoCount: place.photoCount,
                bestPhoto: place.bestPhoto
            )
        }
        let tallies = rows.map { key, row in
            ShownTally(id: key, photoCount: row.photoCount, bestScore: row.bestPhoto.score)
        }
        return ShownRanking.ranked(tallies).compactMap { rows[$0.id] }
    }
}

/// The spots and places around the middle of the map, ranked by how many
/// graded photos people chose to show there. A tap on a row goes to it on
/// the map.
///
/// The photos are other people's, so a row shows the image and a count and
/// nothing about who took it.
struct SpotRankingList: View {
    let rows: [RankedRow]
    /// Called with the row the user picked.
    let select: (RankedRow.Target) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            select(row.target)
                        } label: {
                            RankedRowLabel(rank: index + 1, row: row)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                    }
                } footer: {
                    Text(
                        "Ranked by how many graded photos people chose to show there. "
                            + "Only a listed spot has a name, directions, and local rules."
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Top spots here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// What one row of the ranked list shows.
private struct RankedRowLabel: View {
    let rank: Int
    let row: RankedRow

    private var kindText: String {
        switch row.target {
        case .spot: "Listed spot"
        case .place: "Shown by photographers"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.condensed(20, relativeTo: .title3))
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 24)
                .accessibilityLabel("Number \(rank)")
            SpotThumbnail(photo: row.bestPhoto, description: "The top voted photo from \(row.title)", use: .pin)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(kindText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.countText)
                .font(.condensed(17, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 4)
        // The whole row takes the tap, not only its words.
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The ranked list filled from the sample spots, for the preview.
private struct RankingPreview: View {
    @Environment(CollectionModel.self) private var model
    @Environment(SpotsModel.self) private var spots

    var body: some View {
        SpotRankingList(
            rows: RankedRow.rows(for: spots.around?.shown ?? ShownAround(), spots: model.airports.flatMap(\.spots))
        ) { _ in }
            .task {
                guard let airport = model.airports.first,
                      let middle = Coordinate(latitude: airport.latitude, longitude: airport.longitude)
                else { return }
                await spots.loadShown(around: middle)
            }
    }
}

#Preview("Ranked list") {
    let sync = SyncCoordinator.preview()
    RankingPreview()
        .environment(SampleData.model())
        .environment(SpotsModel.preview(session: sync.session))
}
