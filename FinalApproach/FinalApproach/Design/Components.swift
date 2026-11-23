import FinalApproachCore
import SwiftUI

/// A photo that fills whatever frame it is given and crops the overflow.
struct PhotoFill: View {
    let image: Image
    /// What the photo shows, read by VoiceOver.
    let description: String

    init(image: Image, description: String) {
        self.image = image
        self.description = description
    }

    /// A sample image from the asset catalog.
    init(imageName: String, description: String) {
        self.init(image: Image(imageName), description: description)
    }

    var body: some View {
        Theme.surface
            .overlay {
                image
                    .resizable()
                    .scaledToFill()
                    // The overflow is clipped from view but would still take
                    // taps, so the image takes none.
                    .allowsHitTesting(false)
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(description)
            .accessibilityAddTraits(.isImage)
    }
}

/// A tier name with its color dot, such as a gold dot and "Gold".
struct TierLabel: View {
    let tier: Tier
    var font: Font = .headline

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.fill(for: tier))
                .frame(width: 9, height: 9)
            Text(tier.displayName)
                .font(font)
                .foregroundStyle(Theme.text(for: tier))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A thin horizontal meter for a score from 0 to 100. It fills to its score
/// the first time it appears.
struct ScoreMeter: View {
    let score: Double
    let tint: Color
    /// Where the meter sits in a group, so a list of meters fills one after
    /// another.
    var order = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFilled = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * (isFilled ? fraction : 0))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : Motion.fill, value: score)
        .onAppear {
            guard !isFilled else { return }
            if reduceMotion {
                isFilled = true
            } else {
                withAnimation(Motion.fill.delay(Motion.delay(for: order))) {
                    isFilled = true
                }
            }
        }
    }

    /// The score as a share of the meter's width.
    private var fraction: CGFloat {
        CGFloat(min(max(score / 100, 0), 1))
    }
}

/// Dims and shrinks a photo tile a little while it is pressed.
struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// The one filled button on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 50
    var font: Font = .headline

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(Theme.ground)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(Theme.ink, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A quieter button that sits beside or under the primary one.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.controlFill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }

    /// The primary button at the height of a secondary one, for a pair of
    /// buttons side by side.
    static var primaryCompact: PrimaryButtonStyle {
        PrimaryButtonStyle(minHeight: 44, font: .subheadline.weight(.semibold))
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A small heading above a group of rows.
struct SectionHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension Double {
    /// A score as the whole number the user sees, such as "83".
    var scoreText: String {
        String(Int(rounded()))
    }
}
