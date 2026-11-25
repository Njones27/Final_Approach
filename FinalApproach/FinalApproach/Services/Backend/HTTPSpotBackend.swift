import FinalApproachCore
import Foundation

/// The spot routes reached over HTTPS. The routes are in
/// `docs/backend.md`.
struct HTTPSpotBackend: SpotBackend {
    let api: SignedInAPI

    init(baseURL: URL, transport: any HTTPTransport, accessToken: @escaping () async throws -> String) {
        api = SignedInAPI(baseURL: baseURL, transport: transport, accessToken: accessToken)
    }

    func airports() async throws -> [Airport] {
        let url = api.baseURL.appending(path: "spots")
        let answer: CatalogAnswer = try api.decode(try await api.call("GET", url))
        return answer.airports.map(\.airport)
    }

    func photos(atSpotID spotID: String) async throws -> [SpotPhoto] {
        let url = api.baseURL.appending(path: "spots").appending(path: spotID).appending(path: "photos")
        let answer: SpotPhotosAnswer = try api.decode(try await api.call("GET", url))
        return answer.photos.map(\.photo)
    }

    func shown(around point: Coordinate) async throws -> ShownAround {
        var url = api.baseURL.appending(path: "places")
        url.append(queryItems: [
            URLQueryItem(name: "latitude", value: Self.degrees(point.latitude)),
            URLQueryItem(name: "longitude", value: Self.degrees(point.longitude)),
        ])
        let answer: AroundAnswer = try api.decode(try await api.call("GET", url))
        return ShownAround(
            spots: answer.spots.map { spot in
                ShownSpot(id: spot.spotID, photoCount: max(spot.photoCount, 1), bestPhoto: spot.bestPhoto.photo)
            },
            // A place that is not on the map cannot have a pin, so it is
            // left out.
            places: answer.places.compactMap { place in
                guard let middle = Coordinate(latitude: place.latitude, longitude: place.longitude) else {
                    return nil
                }
                return ShownPlace(
                    id: place.id,
                    coordinate: middle,
                    photoCount: max(place.photoCount, 1),
                    bestPhoto: place.bestPhoto.photo
                )
            }
        )
    }

    func photos(atPlaceID placeID: String) async throws -> [SpotPhoto] {
        let url = api.baseURL.appending(path: "places").appending(path: placeID).appending(path: "photos")
        let answer: SpotPhotosAnswer = try api.decode(try await api.call("GET", url))
        return answer.photos.map(\.photo)
    }

    /// A number of degrees written with two decimals, which is how the
    /// backend reads a point to look around.
    ///
    /// Two decimals is about a kilometer. That is as fine as the backend
    /// needs to pick the part of the map to read, so nothing finer about
    /// where the user is looking is sent.
    static func degrees(_ value: Double) -> String {
        let hundredths = Int((value * 100).rounded())
        let whole = abs(hundredths) / 100
        let part = abs(hundredths) % 100
        return "\(hundredths < 0 ? "-" : "")\(whole).\(part < 10 ? "0" : "")\(part)"
    }

    func image(from url: URL) async throws -> Data? {
        try await api.linkedImage(from: url)
    }
}

// MARK: - What comes over the wire

private struct CatalogAnswer: Decodable {
    struct SpotAnswer: Decodable {
        let id: String
        let name: String
        let summary: String
        let latitude: Double
        let longitude: Double
        let accessNotes: String?
        let localRules: String?
        let runwayNotes: String?
        let viewBearing: Double?

        var spot: Spot {
            Spot(
                id: id,
                name: name,
                summary: summary,
                latitude: latitude,
                longitude: longitude,
                accessNotes: accessNotes ?? "",
                localRules: localRules ?? "",
                runwayNotes: runwayNotes ?? "",
                // A direction that is not on the compass is left out.
                viewBearing: viewBearing.flatMap { (0..<360).contains($0) ? $0 : nil }
            )
        }
    }

    struct AirportAnswer: Decodable {
        let code: String
        let city: String
        let latitude: Double
        let longitude: Double
        let spots: [SpotAnswer]

        var airport: Airport {
            Airport(
                id: code,
                city: city,
                latitude: latitude,
                longitude: longitude,
                // A spot that is not a real place cannot go on the map, so
                // it is left out.
                spots: spots.map(\.spot).filter { $0.coordinate != nil }
            )
        }
    }

    let airports: [AirportAnswer]
}

private struct SpotPhotosAnswer: Decodable {
    struct Photo: Decodable {
        let id: String
        let imageURL: URL
        let score: Int
        let aircraftType: String?
        let airline: String?
        let camera: ShownCamera?

        var photo: SpotPhoto {
            SpotPhoto(
                id: id,
                imageURL: imageURL,
                score: min(max(score, 0), 100),
                aircraftType: aircraftType,
                airline: airline,
                camera: camera
            )
        }
    }

    let photos: [Photo]
}

/// What the backend answers about the spots and places around a point.
private struct AroundAnswer: Decodable {
    struct SpotAnswer: Decodable {
        let spotID: String
        let photoCount: Int
        let bestPhoto: SpotPhotosAnswer.Photo
    }

    struct PlaceAnswer: Decodable {
        let id: String
        let latitude: Double
        let longitude: Double
        let photoCount: Int
        let bestPhoto: SpotPhotosAnswer.Photo
    }

    let spots: [SpotAnswer]
    let places: [PlaceAnswer]
}
