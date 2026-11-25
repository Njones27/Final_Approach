import SwiftUI

/// One photo on a dark ground, as large as the screen allows.
///
/// The photo fits whichever way the phone is held, so a wide photo fills
/// the screen once the phone is turned on its side. It shows the photo and
/// nothing else, which keeps a vote blind. A pinch zooms in, and two taps
/// zoom in and back out.
struct PhotoViewer: View {
    let image: Image
    /// What VoiceOver reads for the photo.
    var label = "The photo"

    @Environment(\.dismiss) private var dismiss
    /// How far the photo is zoomed once the fingers lift.
    @State private var zoom: CGFloat = 1
    /// How far the pinch under way has changed the zoom.
    @GestureState private var pinch: CGFloat = 1

    /// The zoom two taps go to.
    private static let tapZoom: CGFloat = 2
    private static let zoomRange: ClosedRange<CGFloat> = 1...4

    private var shownZoom: CGFloat {
        min(max(zoom * pinch, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.scrim
                .ignoresSafeArea()

            image
                .resizable()
                .scaledToFit()
                .scaleEffect(shownZoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .updating($pinch) { value, pinch, _ in
                            pinch = value.magnification
                        }
                        .onEnded { value in
                            let settled = min(
                                max(zoom * value.magnification, Self.zoomRange.lowerBound),
                                Self.zoomRange.upperBound
                            )
                            withAnimation(Motion.press) {
                                zoom = settled
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(Motion.swap) {
                        zoom = zoom > 1 ? 1 : Self.tapZoom
                    }
                }
                .ignoresSafeArea()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(Theme.onPhoto)
                    .frame(width: 44, height: 44)
                    .background(Theme.scrim.opacity(0.5), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding(12)
        }
        .statusBarHidden()
        .accessibilityAction(.escape) { dismiss() }
    }
}

#Preview("Wide photo") {
    PhotoViewer(image: Image(SampleData.voteQueue[0].imageName))
}
