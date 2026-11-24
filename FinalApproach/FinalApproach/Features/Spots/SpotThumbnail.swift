import SwiftUI
import UIKit

/// The image of one photo on a spot's page. It fills its frame, and shows
/// a plain fill until the image arrives or when it cannot be loaded.
///
/// The photo is another person's, so all it has to show is the image.
struct SpotThumbnail: View {
    let photo: SpotPhoto
    /// What the photo shows, read by VoiceOver.
    let description: String

    @Environment(SpotsModel.self) private var spots
    @State private var image: UIImage?

    var body: some View {
        Theme.controlFill
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        // The overflow is clipped from view but would still
                        // take taps, so the image takes none.
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(Motion.reveal, value: image != nil)
            .accessibilityElement()
            .accessibilityLabel(description)
            .accessibilityAddTraits(.isImage)
            // A link works for a few minutes. When the page is asked for
            // again the photo comes with a new one, and the image is tried
            // again.
            .task(id: photo.imageURL) {
                if let loaded = await spots.thumbnail(for: photo) {
                    image = loaded
                }
            }
    }
}
