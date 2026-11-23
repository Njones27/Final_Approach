import FinalApproachCore
import SwiftUI

/// A grade placed on a 0 to 100 scale that is split at the tier thresholds,
/// so the photographer can see how far the next tier is. The marker travels
/// up the scale to the grade the first time it appears.
struct TierScaleView: View {
    let score: Double
    let thresholds: TierThresholds

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlaced = false

    private let gap: CGFloat = 2
    private let markerSize: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(Tier.allCases, id: \.self) { tier in
                            Rectangle()
                                .fill(Theme.fill(for: tier))
                                .frame(width: segmentWidth(for: tier, in: width))
                        }
                    }
                    .frame(height: 4)
                    .clipShape(Capsule())

                    Circle()
                        .fill(Theme.ink)
                        .padding(3)
                        .background(Theme.ground, in: Circle())
                        .frame(width: markerSize, height: markerSize)
                        .offset(x: isPlaced ? markerOffset(in: width) : 0)
                }
                .frame(height: markerSize)

                HStack(spacing: gap) {
                    ForEach(Tier.allCases, id: \.self) { tier in
                        Text(label(for: tier))
                            .font(.condensed(14, weight: .medium, relativeTo: .caption))
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .frame(width: segmentWidth(for: tier, in: width), alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .animation(reduceMotion ? nil : Motion.settle, value: score)
        .onAppear {
            guard !isPlaced else { return }
            if reduceMotion {
                isPlaced = true
            } else {
                withAnimation(Motion.settle.delay(Motion.arrival)) {
                    isPlaced = true
                }
            }
        }
    }

    /// The highest score in a tier's part of the scale.
    private func upperBound(of tier: Tier) -> Double {
        guard let next = Tier(rawValue: tier.rawValue + 1) else { return 100 }
        return thresholds.lowerBound(of: next)
    }

    private func segmentWidth(for tier: Tier, in width: CGFloat) -> CGFloat {
        let gaps = gap * CGFloat(Tier.allCases.count - 1)
        let share = CGFloat((upperBound(of: tier) - thresholds.lowerBound(of: tier)) / 100)
        return max((width - gaps) * share, 0)
    }

    private func markerOffset(in width: CGFloat) -> CGFloat {
        let clamped = CGFloat(min(max(score, 0), 100))
        let center = width * clamped / 100
        return min(max(center - markerSize / 2, 0), max(width - markerSize, 0))
    }

    private func label(for tier: Tier) -> String {
        tier == .logged ? tier.displayName : thresholds.lowerBound(of: tier).scoreText
    }

    private var accessibilityText: String {
        "Grade \(score.scoreText) on the tier scale. "
            + "Bronze starts at \(thresholds.bronze.scoreText), "
            + "Silver at \(thresholds.silver.scoreText), "
            + "Gold at \(thresholds.gold.scoreText)."
    }
}

#Preview {
    VStack(spacing: 32) {
        TierScaleView(score: 83, thresholds: SampleData.thresholds)
        TierScaleView(score: 58, thresholds: SampleData.thresholds)
        TierScaleView(score: 12, thresholds: SampleData.thresholds)
    }
    .padding(20)
    .background(Theme.ground)
}
