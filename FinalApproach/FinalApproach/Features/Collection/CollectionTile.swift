import FinalApproachCore
import SwiftUI

/// One photo in the collection grid, with its name and grade over a scrim.
/// A tile can stand for one photo or for a slot, which shows its best photo.
struct CollectionTile: View {
    let photo: SpottedPhoto
    /// The leading tile is taller and shows the registration and tier name.
    let isHero: Bool
    /// The name to show in place of the aircraft type, such as an airline
    /// when the tile stands for an airline slot.
    var title: String?
    /// How many shots the slot holds. A slot with more than one says so.
    var shotCount = 1

    private var shownTitle: String {
        title ?? photo.typeTitle
    }

    @Environment(CollectionModel.self) private var model

    var body: some View {
        PhotoFill(image: model.image(for: photo), description: photo.imageDescription)
            .frame(maxWidth: .infinity)
            .frame(height: isHero ? 258 : 146)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Theme.scrim.opacity(0), Theme.scrim.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: isHero ? 130 : 84)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                labels
                    .padding(.horizontal, isHero ? 16 : 10)
                    .padding(.bottom, isHero ? 14 : 9)
                    // Labels sit on the dark scrim in both appearances, so
                    // they always use the dark values.
                    .environment(\.colorScheme, .dark)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    private var labels: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shownTitle)
                    .font(isHero ? .title3.weight(.bold) : .subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onPhoto)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isHero {
                    HStack(spacing: 10) {
                        if let registration = photo.visibleRegistration {
                            Text(registration)
                                .font(.condensed(17, weight: .medium, relativeTo: .subheadline))
                                .tracking(1)
                                .foregroundStyle(Theme.onPhoto)
                        }
                        if model.finalScore(for: photo) != nil {
                            TierLabel(tier: model.tier(for: photo), font: .subheadline.weight(.semibold))
                        }
                    }
                }
                if case let .voting(_, hoursLeft) = photo.status {
                    badge("Voting, \(hoursLeft) h left")
                }
                if shotCount > 1 {
                    badge("\(shotCount) shots")
                }
            }
            Spacer(minLength: 0)
            if let score = model.finalScore(for: photo) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if !isHero {
                        Circle()
                            .fill(Theme.fill(for: model.tier(for: photo)))
                            .frame(width: 8, height: 8)
                    }
                    Text(score.scoreText)
                        .font(.condensed(isHero ? 44 : 26, relativeTo: .title))
                        .foregroundStyle(Theme.onPhoto)
                }
            } else if let reading = model.provisionalScore(for: photo) {
                // The technical reading stands in until the votes are in.
                // It is dimmed and has no tier mark, because the tier comes
                // from votes alone.
                Text(reading.scoreText)
                    .font(.condensed(isHero ? 44 : 26, relativeTo: .title))
                    .foregroundStyle(Theme.onPhoto.opacity(0.6))
            }
        }
    }

    /// A small label on the photo, such as how many shots a slot holds.
    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.onPhoto)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.onPhoto.opacity(0.22), in: Capsule())
    }

    private var accessibilityText: String {
        var parts = [shownTitle]
        if shotCount > 1 {
            parts.append("\(shotCount) shots")
        }
        if let registration = photo.visibleRegistration {
            parts.append(registration)
        }
        switch photo.status {
        case .logged:
            parts.append("not graded yet")
            parts.append(contentsOf: readingText)
        case let .voting(_, hoursLeft):
            parts.append("voting, \(hoursLeft) hours left")
            parts.append(contentsOf: readingText)
        case .graded:
            if let score = model.finalScore(for: photo) {
                parts.append("\(model.tier(for: photo).displayName), grade \(score.scoreText)")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// The technical reading in words, for a photo with no grade yet.
    private var readingText: [String] {
        guard let reading = model.provisionalScore(for: photo) else { return [] }
        return ["technical reading \(reading.scoreText)"]
    }
}

#Preview {
    let model = SampleData.model()
    return VStack(spacing: 2) {
        CollectionTile(photo: model.photos[0], isHero: true)
        CollectionTile(photo: model.photos[5], isHero: false)
    }
    .environment(model)
}
