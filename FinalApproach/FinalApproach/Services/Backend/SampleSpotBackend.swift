import Foundation

/// The spots and their photos kept in memory, for previews and tests. It
/// follows the real backend's rules. A spot that is not listed has no page,
/// and a page gives its photos best first.
final class SampleSpotBackend: SpotBackend {
    /// One graded photo shown at a spot.
    struct Photo {
        let id: String
        let image: Data
        let score: Int
        var aircraftType: String?
        var airline: String?
    }

    private var listed: [Airport]
    /// The photos shown at each spot, by spot id.
    private var shown: [String: [Photo]]
    /// How many photos one page holds.
    private let photosPerSpot: Int
    private(set) var catalogCount = 0
    /// How many times each spot's page was asked for, by spot id.
    private(set) var pageCounts: [String: Int] = [:]
    /// Makes every request for the list of spots fail with this.
    var catalogFailure: PhotoBackendError?
    /// Makes every request for a spot's photos fail with this.
    var pageFailure: PhotoBackendError?

    init(airports: [Airport], photos: [String: [Photo]] = [:], photosPerSpot: Int = 30) {
        listed = airports
        shown = photos
        self.photosPerSpot = photosPerSpot
    }

    func airports() async throws -> [Airport] {
        catalogCount += 1
        if let catalogFailure { throw catalogFailure }
        return listed
    }

    func photos(atSpotID spotID: String) async throws -> [SpotPhoto] {
        pageCounts[spotID, default: 0] += 1
        if let pageFailure { throw pageFailure }
        guard listed.contains(where: { airport in airport.spots.contains { $0.id == spotID } }) else {
            throw PhotoBackendError.unknownSpot
        }
        let best = (shown[spotID] ?? []).sorted { $0.score > $1.score }.prefix(photosPerSpot)
        return best.map { photo in
            SpotPhoto(
                id: photo.id,
                imageURL: Self.imageURL(forPhotoID: photo.id),
                score: photo.score,
                aircraftType: photo.aircraftType,
                airline: photo.airline
            )
        }
    }

    func image(from url: URL) async throws -> Data? {
        let id = url.lastPathComponent
        for photos in shown.values {
            if let photo = photos.first(where: { $0.id == id }) {
                return photo.image
            }
        }
        return nil
    }

    /// Replaces the list of spots, as a deploy of the backend does.
    func list(_ airports: [Airport]) {
        listed = airports
    }

    /// Shows a graded photo at a spot, as its owner would.
    func show(_ photo: Photo, atSpotID spotID: String) {
        shown[spotID, default: []].append(photo)
    }

    /// Takes a photo off every page, as deleting it does.
    func remove(photoID: String) {
        for spotID in shown.keys {
            shown[spotID]?.removeAll { $0.id == photoID }
        }
    }

    /// A stand in for the link the real backend gives to an image.
    static func imageURL(forPhotoID id: String) -> URL {
        URL(filePath: "/sample-backend/spots").appending(path: id)
    }
}
