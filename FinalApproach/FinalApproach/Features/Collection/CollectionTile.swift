import FinalApproachCore
import SwiftUI

/// One photo in the collection grid, with its type and grade over a scrim.
struct CollectionTile: View {
    let photo: SpottedPhoto
    /// The leading tile is taller and shows the registration and tier name.
    let isHero: Bool

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
                Text(photo.aircraftType)
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
                    Text("Voting, \(hoursLeft) h left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.onPhoto)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.onPhoto.opacity(0.22), in: Capsule())
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
            }
        }
    }

    private var accessibilityText: String {
        var parts = [photo.aircraftType]
        if let registration = photo.visibleRegistration {
            parts.append(registration)
        }
        switch photo.status {
        case .logged:
            parts.append("not graded yet")
        case let .voting(_, hoursLeft):
            parts.append("voting, \(hoursLeft) hours left")
        case .graded:
            if let score = model.finalScore(for: photo) {
                parts.append("\(model.tier(for: photo).displayName), grade \(score.scoreText)")
            }
        }
        return parts.joined(separator: ", ")
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
