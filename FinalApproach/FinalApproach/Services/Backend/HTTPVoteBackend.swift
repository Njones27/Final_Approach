import Foundation

/// The voting routes reached over HTTPS. The routes are in
/// `docs/backend.md`.
struct HTTPVoteBackend: VoteBackend {
    let api: SignedInAPI

    init(baseURL: URL, transport: any HTTPTransport, accessToken: @escaping () async throws -> String) {
        api = SignedInAPI(baseURL: baseURL, transport: transport, accessToken: accessToken)
    }

    func queue() async throws -> VoteQueue {
        let url = api.baseURL.appending(path: "votes").appending(path: "queue")
        let answer: QueueAnswer = try api.decode(try await api.call("GET", url))
        return VoteQueue(
            posts: answer.posts.map { VotePost(id: $0.postID, imageURL: $0.imageURL) },
            scaleMax: answer.scaleMax
        )
    }

    func image(from url: URL) async throws -> Data? {
        // The link carries its own permission, so no token is sent with it.
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await api.transport.send(request)
        switch response.statusCode {
        case 200..<300:
            return data
        case 403, 404:
            // The storage answers this way for an image that is not there
            // and for a link that ran out.
            return nil
        default:
            throw PhotoBackendError.unavailable(status: response.statusCode)
        }
    }

    func cast(_ value: Int, onPostID postID: String) async throws {
        let url = api.baseURL.appending(path: "votes").appending(path: postID)
        let body = try JSONEncoder().encode(VoteBody(value: value))
        _ = try await api.call("PUT", url, body: body)
    }
}

// MARK: - What goes over the wire

private struct VoteBody: Encodable {
    /// A whole number of stars.
    let value: Int
}

private struct QueueAnswer: Decodable {
    struct Post: Decodable {
        let postID: String
        let imageURL: URL
    }

    let posts: [Post]
    let scaleMax: Int?
}
