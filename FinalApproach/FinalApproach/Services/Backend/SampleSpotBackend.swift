import FinalApproachCore
import Foundation

/// The spots and their photos kept in memory, for previews and tests. It
/// follows the real backend's rules. A spot that is not listed has no page,
/// a page gives its photos best first, and the map is told only about the
/// spots and places near the point it asks about.
final class SampleSpotBackend: SpotBackend {
    /// One graded photo shown at a spot or a place.
    struct Photo {
        let id: String
        let image: Data
        let score: Int
        var aircraftType: String?
        var airline: String?
        var camera: ShownCamera?
    }

    /// The photos shown at one place, with the middle of its cell.
    private struct Place {
        let middle: Coordinate
        var photos: [Photo] = []
    }

    private var listed: [Airport]
    /// The photos shown at each spot, by spot id.
    private var shown: [String: [Photo]]
    /// The places that have photos, by place id.
    private var places: [String: Place] = [:]
    /// How far from a point, in meters, the map is told about. The real
    /// backend reads the tiles around the point, which reach about as far.
    private let reach: Double
    /// How many times the map asked what is shown around a point.
    private(set) var aroundCount = 0
    /// How many times each place's page was asked for, by place id.
    private(set) var placePageCounts: [String: Int] = [:]
    /// Makes every request for what is shown around a point fail with this.
    var aroundFailure: PhotoBackendError?
    /// How many photos one page holds.
    private let photosPerSpot: Int
    private(set) var catalogCount = 0
    /// How many times each spot's page was asked for, by spot id.
    private(set) var pageCounts: [String: Int] = [:]
    /// Makes every request for the list of spots fail with this.
    var catalogFailure: PhotoBackendError?
    /// Makes every request for a spot's photos fail with this.
    var pageFailure: PhotoBackendError?

    init(airports: [Airport], photos: [String: [Photo]] = [:], photosPerSpot: Int = 30, reach: Double = 50_000) {
        listed = airports
        shown = photos
        self.photosPerSpot = photosPerSpot
        self.reach = reach
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
        return page(of: shown[spotID] ?? [])
    }

    func shown(around point: Coordinate) async throws -> ShownAround {
        aroundCount += 1
        if let aroundFailure { throw aroundFailure }
        var around = ShownAround()
        for spot in listed.flatMap(\.spots) {
            guard let pin = spot.coordinate, pin.distance(to: point) <= reach,
                  let best = page(of: shown[spot.id] ?? []).first
            else { continue }
            around.spots.append(ShownSpot(id: spot.id, photoCount: shown[spot.id]?.count ?? 0, bestPhoto: best))
        }
        for (id, place) in places.sorted(by: { $0.key < $1.key }) {
            guard place.middle.distance(to: point) <= reach, let best = page(of: place.photos).first else {
                continue
            }
            around.places.append(
                ShownPlace(id: id, coordinate: place.middle, photoCount: place.photos.count, bestPhoto: best)
            )
        }
        return around
    }

    func photos(atPlaceID placeID: String) async throws -> [SpotPhoto] {
        placePageCounts[placeID, default: 0] += 1
        if let pageFailure { throw pageFailure }
        // A place is any cell of the map, so one with no photos has an
        // empty page.
        return page(of: places[placeID]?.photos ?? [])
    }

    func image(from url: URL) async throws -> Data? {
        let id = url.lastPathComponent
        let everyPhoto = shown.values.joined() + places.values.flatMap(\.photos)
        return everyPhoto.first { $0.id == id }?.image
    }

    /// The photos as a page gives them, best first.
    private func page(of photos: [Photo]) -> [SpotPhoto] {
        photos.sorted { $0.score > $1.score }.prefix(photosPerSpot).map { photo in
            SpotPhoto(
                id: photo.id,
                imageURL: Self.imageURL(forPhotoID: photo.id),
                score: photo.score,
                aircraftType: photo.aircraftType,
                airline: photo.airline,
                camera: photo.camera
            )
        }
    }

    /// Replaces the list of spots, as a deploy of the backend does.
    func list(_ airports: [Airport]) {
        listed = airports
    }

    /// Shows a graded photo at a spot, as its owner would.
    func show(_ photo: Photo, atSpotID spotID: String) {
        shown[spotID, default: []].append(photo)
    }

    /// Shows a graded photo at a place, as its owner would. The middle of
    /// the place's cell is all the backend keeps of where it is.
    func show(_ photo: Photo, atPlaceID placeID: String, middle: Coordinate) {
        places[placeID, default: Place(middle: middle)].photos.append(photo)
    }

    /// Takes a photo off every page and place, as deleting it does.
    func remove(photoID: String) {
        for spotID in shown.keys {
            shown[spotID]?.removeAll { $0.id == photoID }
        }
        for placeID in places.keys {
            places[placeID]?.photos.removeAll { $0.id == photoID }
        }
    }

    /// A stand in for the link the real backend gives to an image.
    static func imageURL(forPhotoID id: String) -> URL {
        URL(filePath: "/sample-backend/spots").appending(path: id)
    }
}
