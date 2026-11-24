import Foundation

/// The backend reached over HTTPS. The routes are in `docs/backend.md`.
struct HTTPPhotoBackend: PhotoBackend {
    /// The address of the API, with no path.
    let baseURL: URL
    let transport: any HTTPTransport
    /// Gives the token that proves who is signed in. It throws
    /// `PhotoBackendError.notSignedIn` when no one is.
    let accessToken: () async throws -> String

    /// The most pages one listing follows. It stops a listing that never
    /// ends from running forever.
    static let maxPages = 500

    // MARK: Routes

    func listPhotos() async throws -> RemoteListing {
        var listing = RemoteListing()
        var after: String?
        for _ in 0..<Self.maxPages {
            var url = baseURL.appending(path: "photos")
            if let after {
                url.append(queryItems: [URLQueryItem(name: "after", value: after)])
            }
            let page: ListAnswer = try decode(try await call("GET", url))
            for entry in page.photos {
                guard let photo = entry.document, photo.id == entry.photoID, !photo.isSample else {
                    listing.unreadableIDs.insert(entry.photoID)
                    continue
                }
                listing.photos.append(
                    RemotePhoto(photo: photo, version: entry.updatedAt, imageURL: entry.imageURL)
                )
            }
            listing.deletedIDs.formUnion(page.deleted.map(\.photoID))
            guard let next = page.nextAfter else { return listing }
            after = next
        }
        throw PhotoBackendError.unreadableAnswer
    }

    func savePhoto(_ photo: SpottedPhoto, image: Data?) async throws -> SavedPhoto {
        guard !photo.isSample else { throw PhotoBackendError.notTheUsersPhoto }
        let url = baseURL.appending(path: "photos").appending(path: photo.id)
        // An empty image is no image. The backend takes no upload of no bytes.
        let payload = image.flatMap { $0.isEmpty ? nil : $0 }
        let body = try JSONEncoder().encode(SaveBody(document: photo, imageBytes: payload?.count))
        let answer: SaveAnswer = try decode(try await call("PUT", url, body: body))

        guard let payload, let upload = answer.upload else {
            return SavedPhoto(version: answer.updatedAt, imageSent: false)
        }
        // The record is saved by now. A failed image is not thrown, so the
        // caller still learns the record's version and sends the image again
        // on the next sync.
        do {
            try await send(payload, to: upload)
            return SavedPhoto(version: answer.updatedAt, imageSent: true)
        } catch {
            #if DEBUG
            print("HTTPPhotoBackend: Sending the image failed. \(error)")
            #endif
            return SavedPhoto(version: answer.updatedAt, imageSent: false)
        }
    }

    func fetchImage(from url: URL) async throws -> Data? {
        // The link carries its own permission, so no token is sent with it.
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await transport.send(request)
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

    func deletePhoto(id: String) async throws {
        _ = try await call("DELETE", baseURL.appending(path: "photos").appending(path: id))
    }

    func deleteAccount() async throws {
        _ = try await call("DELETE", baseURL.appending(path: "account"))
    }

    // MARK: Requests

    /// Sends a signed in request to the API and returns the body of a
    /// successful answer.
    private func call(_ method: String, _ url: URL, body: Data? = nil) async throws -> Data {
        try await api.call(method, url, body: body)
    }

    /// Sends an image to the link the backend gave for it.
    private func send(_ image: Data, to upload: SaveAnswer.Upload) async throws {
        var request = URLRequest(url: upload.url)
        request.httpMethod = upload.method
        for (name, value) in upload.headers where name.lowercased() != "content-length" {
            // The system sets the length from the body. The link is signed
            // for the size the app declared, which is this same body.
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = image
        let (_, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw PhotoBackendError.unavailable(status: response.statusCode)
        }
    }

    private func decode<Answer: Decodable>(_ data: Data) throws -> Answer {
        try api.decode(data)
    }

    /// The caller every signed in route shares.
    private var api: SignedInAPI {
        SignedInAPI(baseURL: baseURL, transport: transport, accessToken: accessToken)
    }

    /// Turns a refusal into the error the app acts on.
    static func problem(status: Int, body: Data) -> PhotoBackendError {
        SignedInAPI.problem(status: status, body: body)
    }
}

// MARK: - What goes over the wire

/// The body of a request to save a photo.
private struct SaveBody: Encodable {
    /// The photo as the app saves it. It can hold where the photo was taken
    /// and a blocked registration, so the backend returns it to its owner
    /// only.
    let document: SpottedPhoto
    /// The size of the image about to be sent. It is left out when there is
    /// no image to send.
    let imageBytes: Int?
}

private struct SaveAnswer: Decodable {
    struct Upload: Decodable {
        let url: URL
        let method: String
        let headers: [String: String]
    }

    let updatedAt: String
    let upload: Upload?
}

private struct ListAnswer: Decodable {
    struct Entry: Decodable {
        let photoID: String
        /// Nil when this version of the app cannot read the record.
        let document: SpottedPhoto?
        let updatedAt: String
        let imageURL: URL

        private enum CodingKeys: String, CodingKey {
            case photoID, document, updatedAt, imageURL
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            photoID = try values.decode(String.self, forKey: .photoID)
            // One record the app cannot read must not hide all the others.
            document = try? values.decode(SpottedPhoto.self, forKey: .document)
            updatedAt = try values.decode(String.self, forKey: .updatedAt)
            imageURL = try values.decode(URL.self, forKey: .imageURL)
        }
    }

    struct Deleted: Decodable {
        let photoID: String
    }

    let photos: [Entry]
    let deleted: [Deleted]
    let nextAfter: String?
}
