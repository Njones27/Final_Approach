import FinalApproachCore
import SwiftUI

/// The tile, card, or thumbnail a photo screen grows out of. One photo can
/// be on screen in two places, so each place has its own case.
enum ZoomSource: Hashable {
    /// The photo that leads the Collection screen.
    case hero(String)
    /// A tile in the Collection grid, by slot id or photo id.
    case tile(String)
    /// A photo inside a slot's own screen.
    case slotPhoto(String)
    /// The card for one of the user's photos on the Spots map.
    case mapCard(String)
}

/// Where a tap on a photo or a slot leads.
enum PhotoRoute: Hashable {
    case photo(id: String, source: ZoomSource)
    case technicalCheck(String)
    case slot(kind: SlotKind, key: String)
}

extension View {
    /// Adds the photo screens to a navigation stack. A photo grows out of
    /// the view that was marked with the same source in `namespace`.
    func photoDestinations(zoomingIn namespace: Namespace.ID) -> some View {
        navigationDestination(for: PhotoRoute.self) { route in
            switch route {
            case let .photo(id, source):
                PhotoDetailView(photoID: id)
                    .navigationTransition(.zoom(sourceID: source, in: namespace))
            case let .technicalCheck(id):
                TechnicalCheckView(photoID: id)
            case let .slot(kind, key):
                SlotView(kind: kind, key: key, zoomNamespace: namespace)
            }
        }
    }
}
