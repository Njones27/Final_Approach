import Foundation

/// One graded photo on a spot's page, as another person may see it.
///
/// The backend gives the image, the grade, and the aircraft type and
/// airline the owner chose to show. There is no photographer, no
/// registration, and no position here, so none of them can be shown by
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
    /// The image behind a link from `photos`, or nil when the link ran out
    /// or the image is gone.
    func image(from url: URL) async throws -> Data?
}
