import SwiftUI

/// The app's shared motion values. Every animation takes its timing from
/// here, so the screens move the same way.
///
/// Motion stays short and eases out, so the screen answers a tap at once and
/// then settles. Anything that travels has a still or fading version for
/// people who turn on Reduce Motion.
enum Motion {
    /// A press, or a small change under the finger.
    static let press = Animation.snappy(duration: 0.2)

    /// One piece of content replacing another, such as the next photo to
    /// vote on or a grid changing its order.
    static let swap = Animation.snappy(duration: 0.32)

    /// Content arriving on a screen that just opened.
    static let reveal = Animation.easeOut(duration: 0.35)

    /// A meter filling to its value.
    static let fill = Animation.easeOut(duration: 0.6)

    /// A marker travelling to its value and settling there.
    static let settle = Animation.spring(duration: 0.6, bounce: 0.18)

    /// Old content fading away before its replacement arrives.
    static let leave = Animation.easeOut(duration: 0.12)

    /// The replacement fading in once the old content has gone.
    static let arrive = Animation.easeOut(duration: 0.22).delay(0.1)

    /// How long content waits after its screen starts to open, so it moves
    /// once the screen has arrived and not while it is still travelling. A
    /// screen takes about a third of a second to open.
    static let arrival = 0.3

    /// The pause between one item in a group and the next.
    static let stagger = 0.04

    /// How far revealed content rises into place.
    static let revealDistance: CGFloat = 10

    /// When the item at `order` in a group starts to move.
    static func delay(for order: Int) -> Double {
        arrival + Double(max(order, 0)) * stagger
    }
}

/// Fades content in and lifts it into place the first time it appears.
private struct RevealOnAppear: ViewModifier {
    let order: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            // With Reduce Motion on the content only fades.
            .offset(y: isShown || reduceMotion ? 0 : Motion.revealDistance)
            .onAppear {
                guard !isShown else { return }
                withAnimation(Motion.reveal.delay(Motion.delay(for: order))) {
                    isShown = true
                }
            }
    }
}

extension AnyTransition {
    /// Old content fades out before its replacement fades in, so two pieces
    /// of text never sit on top of each other.
    static var fadeThrough: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(Motion.arrive),
            removal: .opacity.animation(Motion.leave)
        )
    }
}

extension View {
    /// Fades the view in and lifts it into place the first time it appears.
    /// Items in a group pass their position as `order`, so they arrive one
    /// after another.
    func revealed(order: Int = 0) -> some View {
        modifier(RevealOnAppear(order: order))
    }
}
