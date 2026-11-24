import FinalApproachCore
import SwiftUI

/// Every shot the user has of one type, airline, or registration. The best
/// one holds the slot and leads the screen.
struct SlotView: View {
    let kind: SlotKind
    let key: String
    let zoomNamespace: Namespace.ID

    @Environment(CollectionModel.self) private var model

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            if let entry = model.slot(kind, key: key) {
                content(for: entry)
            } else {
                ContentUnavailableView(
                    "No photos here",
                    systemImage: "square.grid.2x2",
                    description: Text("The photos in this slot were removed.")
                )
            }
        }
        .background(Theme.ground)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for entry: CollectionEntry) -> some View {
        let photos = model.photos(in: entry)
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                summary(for: entry)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                if let best = photos.first {
                    tile(for: best, isHero: true)
                }
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(photos.dropFirst()) { photo in
                        tile(for: photo, isHero: false)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(entry.title)
    }

    private func summary(for entry: CollectionEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TierLabel(tier: entry.tier)
            Text(summaryText(for: entry))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// How many shots the slot holds, and when a better one last took it.
    private func summaryText(for entry: CollectionEntry) -> String {
        let count = entry.photoIDs.count
        let shots = count == 1 ? "1 shot." : "\(count) shots. The best one holds the slot."
        guard let upgradedAt = entry.upgradedAt else { return shots }
        return "\(shots) Upgraded \(upgradedAt.formatted(date: .abbreviated, time: .omitted))."
    }

    private func tile(for photo: SpottedPhoto, isHero: Bool) -> some View {
        let source = ZoomSource.slotPhoto(photo.id)
        return NavigationLink(value: PhotoRoute.photo(id: photo.id, source: source)) {
            CollectionTile(photo: photo, isHero: isHero)
                .matchedTransitionSource(id: source, in: zoomNamespace)
        }
        .buttonStyle(TilePressStyle())
    }
}

#Preview {
    @Previewable @Namespace var namespace
    NavigationStack {
        SlotView(kind: .airline, key: "us air force", zoomNamespace: namespace)
            .photoDestinations(zoomingIn: namespace)
    }
    .environment(SampleData.model())
}
