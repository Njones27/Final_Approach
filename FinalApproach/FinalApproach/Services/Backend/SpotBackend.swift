import FinalApproachCore
import Foundation

/// One graded photo on a spot's page or at a place, as another person may
/// see it.
///
/// The backend gives the image, the grade, and the aircraft type, airline,
/// and camera settings the owner chose to show. There is no photographer,
/// no registration, and no position here, so none of them can be shown by
/// mistake.
struct SpotPhoto: Equatable, Identifiable {
    /// The post's random id. It does not name the owner or the photo.
    let id: String
    /// A link to the image that works for a few minutes.
    let imageURL: URL
    /// The final grade from 0 to 100.
    let score: Int
    var aircraftType: String?
    var airline: String?
    /// How the photo was taken, when its owner shows that.
    var camera: ShownCamera?
}

/// What is shown at one listed spot, as the map needs it.
struct ShownSpot: Equatable, Identifiable {
    /// The spot's id.
    let id: String
    /// How many graded photos are shown there.
    let photoCount: Int
    /// The photo the votes graded highest there.
    let bestPhoto: SpotPhoto
}

/// What is shown at one place, which is a cell of the map about a hundred
/// meters across that people chose to show photos from.
struct ShownPlace: Equatable, Identifiable {
    /// The place's id, such as `n33640w84428`.
    let id: String
    /// The middle of the place's cell. Nothing finer is known about where
    /// its photos were taken.
    let coordinate: Coordinate
    /// How many graded photos are shown there.
    let photoCount: Int
    /// The photo the votes graded highest there.
    let bestPhoto: SpotPhoto
}

/// Everything shown around one point of the map.
struct ShownAround: Equatable {
    /// The listed spots that have photos.
    var spots: [ShownSpot] = []
    var places: [ShownPlace] = []
}

/// The backend's routes for the curated spots and the photos shown there.
///
/// It sits behind a protocol so the Spots screen can be built, previewed,
/// and tested with no network.
protocol SpotBackend {
    /// Every listed spot, grouped by airport. The backend owns the list,
    /// so it changes with no release.
    func airports() async throws -> [Airport]
    /// The best graded photos shown at one spot, best first.
    func photos(atSpotID spotID: String) async throws -> [SpotPhoto]
    /// The spots and places around a point that have photos, each with how
    /// many it has and the one the votes graded highest.
    func shown(around point: Coordinate) async throws -> ShownAround
    /// The best graded photos shown at one place, best first.
    func photos(atPlaceID placeID: String) async throws -> [SpotPhoto]
    /// The image behind a link from `photos`, or nil when the link ran out
    /// or the image is gone.
    func image(from url: URL) async throws -> Data?
}
