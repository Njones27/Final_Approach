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
        return answer.photos.map { photo in
            SpotPhoto(
                id: photo.id,
                imageURL: photo.imageURL,
                score: min(max(photo.score, 0), 100),
                aircraftType: photo.aircraftType,
                airline: photo.airline
            )
        }
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

        var spot: Spot {
            Spot(
                id: id,
                name: name,
                summary: summary,
                latitude: latitude,
                longitude: longitude,
                accessNotes: accessNotes ?? "",
                localRules: localRules ?? "",
                runwayNotes: runwayNotes ?? ""
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
    }

    let photos: [Photo]
}
