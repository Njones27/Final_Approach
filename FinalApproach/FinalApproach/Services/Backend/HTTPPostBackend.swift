import FinalApproachCore
import Foundation

/// The posting routes reached over HTTPS. The routes are in
/// `docs/backend.md`.
struct HTTPPostBackend: PostBackend {
    let api: SignedInAPI
    /// The grid the backend cuts the map into, which says where the middle
    /// of a place's cell is.
    let placeGrid: PlaceGrid

    /// The most pages one listing follows. It stops a listing that never
    /// ends from running forever.
    static let maxPages = 500

    init(
        baseURL: URL,
        transport: any HTTPTransport,
        placeGrid: PlaceGrid,
        accessToken: @escaping () async throws -> String
    ) {
        api = SignedInAPI(baseURL: baseURL, transport: transport, accessToken: accessToken)
        self.placeGrid = placeGrid
    }

    func post(photoID: String) async throws -> PostStanding {
        let url = api.baseURL.appending(path: "posts").appending(path: photoID)
        // The request has no body. The backend knows the photo by its id,
        // and nothing about it is sent again.
        let answer: PostAnswer = try api.decode(try await api.call("PUT", url))
        guard answer.photoID == photoID, let standing = answer.standing else {
            throw PhotoBackendError.unreadableAnswer
        }
        return standing
    }

    func listPosts() async throws -> PostListing {
        var listing = PostListing()
        var after: String?
        for _ in 0..<Self.maxPages {
            var url = api.baseURL.appending(path: "posts")
            if let after {
                url.append(queryItems: [URLQueryItem(name: "after", value: after)])
            }
            let page: ListAnswer = try api.decode(try await api.call("GET", url))
            for post in page.posts {
                // A post this version cannot read is left out. The photo
                // then shows as it did before.
                guard let standing = post.standing else { continue }
                listing.standings[post.photoID] = standing
                // A photo shown somewhere this version does not know is
                // read as shown nowhere.
                if let shownAt = post.shownAt, shownAt.isSomewhere {
                    listing.showings[post.photoID] = shownAt
                }
            }
            listing.minimumVotes = page.minVotes
            guard let next = page.nextAfter else { return listing }
            after = next
        }
        throw PhotoBackendError.unreadableAnswer
    }

    func show(photoID: String, at showing: SpotShowing) async throws -> SpotShowing {
        let url = spotURL(forPhotoID: photoID)
        // The body names a listed spot, or gives the middle of a place's
        // cell, with what to show beside the photo. Where the photo was
        // taken is not in it, and neither is anything else about the photo.
        var request = ShowRequest(
            aircraftType: showing.aircraftType,
            airline: showing.airline,
            camera: showing.camera
        )
        if let spotID = showing.spotID {
            request.spotID = spotID
        } else if let placeID = showing.placeID, let middle = placeGrid.center(ofPlaceID: placeID) {
            request.place = middle
        } else {
            // The showing names nowhere this grid knows.
            throw PhotoBackendError.unknownSpot
        }
        let body = try JSONEncoder().encode(request)
        let answer: ShowAnswer = try api.decode(try await api.call("PUT", url, body: body))
        guard answer.photoID == photoID, answer.shownAt.isSomewhere else {
            throw PhotoBackendError.unreadableAnswer
        }
        return answer.shownAt
    }

    func hide(photoID: String) async throws {
        _ = try await api.call("DELETE", spotURL(forPhotoID: photoID))
    }

    private func spotURL(forPhotoID photoID: String) -> URL {
        api.baseURL.appending(path: "posts").appending(path: photoID).appending(path: "spot")
    }
}

// MARK: - What comes over the wire

/// What is sent to show a photo. It names a listed spot or gives the
/// middle of a place's cell, and never both.
private struct ShowRequest: Encodable {
    var spotID: String?
    /// The middle of the cell the photo is shown at. The backend keeps the
    /// cell and drops the position.
    var place: GeoPoint?
    var aircraftType: String?
    var airline: String?
    var camera: ShownCamera?
}

/// What the backend answers when a photo is put on a spot's page or at a
/// place.
private struct ShowAnswer: Decodable {
    let photoID: String
    let shownAt: SpotShowing
}

/// One post as its owner is told about it.
private struct PostAnswer: Decodable {
    let photoID: String
    let postedAt: String
    let closesAt: String
    let voteCount: Int
    /// "voting" while the vote is open and "final" once the grade is set.
    let status: String
    /// The grade from 0 to 100. The backend sends it only once it is final.
    let score: Int?
    /// Where the photo is shown, when it is shown anywhere.
    let shownAt: SpotShowing?

    /// The standing, or nil when a time cannot be read or the answer says
    /// the grade is final and gives none.
    var standing: PostStanding? {
        guard let posted = BackendTime.date(from: postedAt), let closes = BackendTime.date(from: closesAt) else {
            return nil
        }
        switch status {
        case "voting":
            return PostStanding(postedAt: posted, closesAt: closes, voteCount: voteCount)
        case "final":
            guard let score else { return nil }
            return PostStanding(postedAt: posted, closesAt: closes, voteCount: voteCount, finalScore: score)
        default:
            return nil
        }
    }
}

private struct ListAnswer: Decodable {
    let posts: [PostAnswer]
    let minVotes: Int?
    let nextAfter: String?
}

/// Reads the times the backend writes, such as "2026-11-24T12:00:00.000Z".
enum BackendTime {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from text: String) -> Date? {
        withFraction.date(from: text) ?? wholeSeconds.date(from: text)
    }
}
