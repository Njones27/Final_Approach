import FinalApproachCore
import Foundation
import Testing

@testable import FinalApproach

/// A transport that answers from a script and remembers what it was sent.
@MainActor
private final class ScriptedTransport: HTTPTransport {
    struct Answer {
        var status = 200
        var body = Data()
    }

    private(set) var requests: [URLRequest] = []
    private var answers: [Answer]

    init(_ answers: [Answer]) {
        self.answers = answers
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !answers.isEmpty, let url = request.url else { throw URLError(.badServerResponse) }
        let answer = answers.removeFirst()
        guard let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return (answer.body, response)
    }
}

/// The app's side of the backend's photo routes.
@MainActor
struct PhotoBackendTests {
    private let base = URL(string: "https://api.example.test")!

    private func photo(_ id: String = "imported-1", type: String = "Boeing 737-800") -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: type,
            registration: "N823AK",
            airline: "Alaska Airlines",
            activity: "",
            loggedAt: Date(timeIntervalSince1970: 1_800_000_000),
            captureCoordinate: Coordinate(latitude: 33.6220, longitude: -84.3995),
            spotID: "atl-south-approach",
            isLocationUndisclosed: true,
            status: .logged
        )
    }

    private func backend(
        _ transport: ScriptedTransport,
        token: @escaping () async throws -> String = { "token-1" }
    ) -> HTTPPhotoBackend {
        HTTPPhotoBackend(baseURL: base, transport: transport, accessToken: token)
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    private func object(_ data: Data?) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: try #require(data))
        return try #require(value as? [String: Any])
    }

    /// One entry of a listing, as the backend sends it.
    private func entry(_ photo: SpottedPhoto, version: String = "2026-11-24T12:00:00.000Z") throws -> [String: Any] {
        [
            "photoID": photo.id,
            "document": try JSONSerialization.jsonObject(with: try JSONEncoder().encode(photo)),
            "updatedAt": version,
            "imageURL": "https://images.example.test/\(photo.id).jpg?signature=abc",
        ]
    }

    private func saveAnswer(upload: Bool) throws -> Data {
        var answer: [String: Any] = ["photoID": "imported-1", "updatedAt": "v2"]
        if upload {
            answer["upload"] = [
                "url": "https://upload.example.test/imported-1.jpg?signature=abc",
                "method": "PUT",
                "headers": ["Content-Type": "image/jpeg", "Content-Length": "3"],
                "expiresInSeconds": 300,
            ]
        }
        return try json(answer)
    }

    // MARK: Listing

    @Test func aListingAsksAsTheSignedInUserAndReadsEveryPart() async throws {
        let first = photo("imported-1")
        let second = photo("imported-2", type: "Airbus A220-300")
        let transport = ScriptedTransport([
            .init(body: try json([
                "photos": [try entry(first, version: "v1"), try entry(second, version: "v2")],
                "deleted": [["photoID": "imported-9", "deletedAt": "2026-11-23T08:00:00.000Z"]],
                "imageLinkExpiresInSeconds": 900,
            ])),
        ])

        let listing = try await backend(transport).listPhotos()

        #expect(listing.photos.map(\.photo) == [first, second])
        #expect(listing.photos.map(\.version) == ["v1", "v2"])
        #expect(listing.photos.first?.imageURL.host() == "images.example.test")
        #expect(listing.deletedIDs == ["imported-9"])
        #expect(listing.unreadableIDs.isEmpty)

        let request = try #require(transport.requests.first)
        #expect(transport.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/photos")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test func aListingFollowsEveryPage() async throws {
        let transport = ScriptedTransport([
            .init(body: try json(["photos": [try entry(photo("imported-1"))], "deleted": [], "nextAfter": "imported-1"])),
            .init(body: try json(["photos": [try entry(photo("imported-2"))], "deleted": [["photoID": "imported-9"]]])),
        ])

        let listing = try await backend(transport).listPhotos()

        #expect(listing.photos.map(\.photo.id) == ["imported-1", "imported-2"])
        #expect(listing.deletedIDs == ["imported-9"])
        #expect(transport.requests.map { $0.url?.absoluteString } == [
            "https://api.example.test/photos",
            "https://api.example.test/photos?after=imported-1",
        ])
    }

    @Test func aRecordTheAppCannotReadDoesNotHideTheOthers() async throws {
        let transport = ScriptedTransport([
            .init(body: try json([
                "photos": [
                    ["photoID": "from-the-future", "document": ["id": "from-the-future", "shape": 2],
                     "updatedAt": "v1", "imageURL": "https://images.example.test/a.jpg"],
                    try entry(photo("imported-1")),
                ],
                "deleted": [],
            ])),
        ])

        let listing = try await backend(transport).listPhotos()

        #expect(listing.photos.map(\.photo.id) == ["imported-1"])
        #expect(listing.unreadableIDs == ["from-the-future"])
    }

    @Test func aRecordFiledUnderAnotherIDIsNotTrusted() async throws {
        var mismatched = try entry(photo("imported-1"))
        mismatched["photoID"] = "imported-2"
        let transport = ScriptedTransport([.init(body: try json(["photos": [mismatched], "deleted": []]))])

        let listing = try await backend(transport).listPhotos()

        #expect(listing.photos.isEmpty)
        #expect(listing.unreadableIDs == ["imported-2"])
    }

    @Test func anAnswerInTheWrongShapeIsAnError() async throws {
        let transport = ScriptedTransport([.init(body: Data("not json".utf8))])
        await #expect(throws: PhotoBackendError.unreadableAnswer) {
            _ = try await backend(transport).listPhotos()
        }
    }

    // MARK: Saving

    @Test func savingSendsTheRecordAndThenTheImageToItsLink() async throws {
        let transport = ScriptedTransport([.init(body: try saveAnswer(upload: true)), .init()])
        let image = Data([1, 2, 3])

        let saved = try await backend(transport).savePhoto(photo(), image: image)

        #expect(saved == SavedPhoto(version: "v2", imageSent: true))
        #expect(transport.requests.count == 2)

        let record = transport.requests[0]
        #expect(record.httpMethod == "PUT")
        #expect(record.url?.absoluteString == "https://api.example.test/photos/imported-1")
        #expect(record.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(record.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try object(record.httpBody)
        #expect(body["imageBytes"] as? Int == 3)
        let document = try #require(body["document"] as? [String: Any])
        #expect(document["id"] as? String == "imported-1")
        #expect(document["aircraftType"] as? String == "Boeing 737-800")

        let upload = transport.requests[1]
        #expect(upload.httpMethod == "PUT")
        #expect(upload.url?.host() == "upload.example.test")
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(upload.httpBody == image)
        // The link carries its own permission. The user's token stays with the API.
        #expect(upload.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func savingWithNoImageSendsOnlyTheRecord() async throws {
        let transport = ScriptedTransport([.init(body: try saveAnswer(upload: false))])

        let saved = try await backend(transport).savePhoto(photo(), image: nil)

        #expect(saved == SavedPhoto(version: "v2", imageSent: false))
        #expect(transport.requests.count == 1)
        #expect(try object(transport.requests[0].httpBody)["imageBytes"] == nil)
    }

    @Test func anEmptyImageCountsAsNoImage() async throws {
        let transport = ScriptedTransport([.init(body: try saveAnswer(upload: false))])

        let saved = try await backend(transport).savePhoto(photo(), image: Data())

        #expect(saved.imageSent == false)
        #expect(try object(transport.requests[0].httpBody)["imageBytes"] == nil)
    }

    @Test func aFailedImageStillReportsTheSavedRecord() async throws {
        let transport = ScriptedTransport([.init(body: try saveAnswer(upload: true)), .init(status: 403)])

        let saved = try await backend(transport).savePhoto(photo(), image: Data([1, 2, 3]))

        #expect(saved == SavedPhoto(version: "v2", imageSent: false))
    }

    @Test func aSamplePhotoIsNeverSent() async throws {
        let transport = ScriptedTransport([])
        let sample = try #require(SampleData.model().photos.first { $0.isSample })

        await #expect(throws: PhotoBackendError.notTheUsersPhoto) {
            _ = try await backend(transport).savePhoto(sample, image: nil)
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Images

    @Test func anImageIsFetchedFromItsLinkWithoutTheUsersToken() async throws {
        let transport = ScriptedTransport([.init(body: Data([9, 8, 7]))])
        let link = try #require(URL(string: "https://images.example.test/imported-1.jpg?signature=abc"))

        let image = try await backend(transport).fetchImage(from: link)

        #expect(image == Data([9, 8, 7]))
        #expect(transport.requests[0].url == link)
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test(arguments: [403, 404])
    func anImageThatIsNotThereGivesNothing(status: Int) async throws {
        let transport = ScriptedTransport([.init(status: status)])
        let link = try #require(URL(string: "https://images.example.test/imported-1.jpg"))
        #expect(try await backend(transport).fetchImage(from: link) == nil)
    }

    @Test func aStorageFailureWhileFetchingAnImageIsAnError() async throws {
        let transport = ScriptedTransport([.init(status: 503)])
        let link = try #require(URL(string: "https://images.example.test/imported-1.jpg"))
        await #expect(throws: PhotoBackendError.unavailable(status: 503)) {
            _ = try await backend(transport).fetchImage(from: link)
        }
    }

    // MARK: Deleting

    @Test func deletingAPhotoAsksTheBackendToDeleteIt() async throws {
        let transport = ScriptedTransport([.init(status: 204)])

        try await backend(transport).deletePhoto(id: "imported-1")

        #expect(transport.requests[0].httpMethod == "DELETE")
        #expect(transport.requests[0].url?.absoluteString == "https://api.example.test/photos/imported-1")
        #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test func deletingTheAccountAsksTheBackendToDeleteIt() async throws {
        let transport = ScriptedTransport([.init(status: 204)])

        try await backend(transport).deleteAccount()

        #expect(transport.requests[0].httpMethod == "DELETE")
        #expect(transport.requests[0].url?.absoluteString == "https://api.example.test/account")
    }

    // MARK: Refusals

    @Test func nothingIsSentWhenNoOneIsSignedIn() async throws {
        let transport = ScriptedTransport([])
        let signedOut = backend(transport) { throw PhotoBackendError.notSignedIn }

        await #expect(throws: PhotoBackendError.notSignedIn) {
            _ = try await signedOut.listPhotos()
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func refusalsBecomeTheErrorsTheAppActsOn() throws {
        func problem(_ status: Int, _ body: [String: Any]) throws -> PhotoBackendError {
            HTTPPhotoBackend.problem(status: status, body: try json(body))
        }
        #expect(try problem(401, ["message": "Unauthorized"]) == .notSignedIn)
        #expect(try problem(410, ["message": "This photo was deleted.", "code": "photoDeleted"]) == .photoDeleted)
        #expect(try problem(410, ["message": "This account was deleted.", "code": "accountDeleted"]) == .accountDeleted)
        #expect(try problem(400, ["message": "The image is too large."])
            == .refused(status: 400, message: "The image is too large."))
        #expect(try problem(503, ["message": "Service Unavailable"]) == .unavailable(status: 503))
        // A body that is not JSON still gives an error with its status.
        #expect(HTTPPhotoBackend.problem(status: 429, body: Data("slow down".utf8))
            == .refused(status: 429, message: ""))
    }

    @Test func aDeletedPhotoRefusesToBeSavedAgain() async throws {
        let transport = ScriptedTransport([
            .init(status: 410, body: try json(["message": "This photo was deleted.", "code": "photoDeleted"])),
        ])
        await #expect(throws: PhotoBackendError.photoDeleted) {
            _ = try await backend(transport).savePhoto(photo(), image: Data([1]))
        }
        // No image is sent for a record the backend did not take.
        #expect(transport.requests.count == 1)
    }

    // MARK: Fingerprints

    @Test func theSameRecordAlwaysGivesTheSameFingerprint() throws {
        #expect(try photo().syncFingerprint() == photo().syncFingerprint())
        #expect(try photo().syncFingerprint().count == 64)
    }

    @Test func anEditedRecordGivesANewFingerprint() throws {
        let edited = photo().replacingDetails(
            aircraftType: "Boeing 737-900",
            registration: nil,
            isRegistrationBlocked: nil,
            airline: "Alaska Airlines"
        )
        #expect(try edited.syncFingerprint() != photo().syncFingerprint())
    }

    @Test func aRecordKeepsItsFingerprintThroughTheBackend() async throws {
        // What comes back from a listing must match what was sent, or every
        // sync would see an edit that never happened.
        let original = photo()
        let transport = ScriptedTransport([.init(body: try json(["photos": [try entry(original)], "deleted": []]))])

        let listed = try #require(try await backend(transport).listPhotos().photos.first)

        #expect(try listed.photo.syncFingerprint() == original.syncFingerprint())
    }

    // MARK: The address

    @Test func aBareHostNameBecomesAnHTTPSAddress() {
        #expect(AppEnvironment.baseURL(forHost: "abc123.execute-api.us-east-1.amazonaws.com")?.absoluteString
            == "https://abc123.execute-api.us-east-1.amazonaws.com")
    }

    @Test(arguments: ["", "api.example.test/path", "user@api.example.test", "https://api.example.test", "api example"])
    func aValueThatIsNotABareHostNameGivesNoAddress(host: String) {
        #expect(AppEnvironment.baseURL(forHost: host) == nil)
    }
}

/// The in-memory backend follows the real one's rules.
@MainActor
struct SamplePhotoBackendTests {
    private func photo(_ id: String) -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: "Boeing 737-800",
            registration: "",
            airline: "",
            activity: "",
            loggedAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .logged
        )
    }

    @Test func aSavedPhotoIsListedWithItsImage() async throws {
        let backend = SamplePhotoBackend()
        let saved = try await backend.savePhoto(photo("a"), image: Data([1, 2]))

        let listing = try await backend.listPhotos()
        let listed = try #require(listing.photos.first)

        #expect(saved.imageSent)
        #expect(listed.photo == photo("a"))
        #expect(listed.version == saved.version)
        #expect(try await backend.fetchImage(from: listed.imageURL) == Data([1, 2]))
    }

    @Test func everySaveGivesANewVersion() async throws {
        let backend = SamplePhotoBackend()
        let first = try await backend.savePhoto(photo("a"), image: nil)
        let second = try await backend.savePhoto(photo("a"), image: nil)
        #expect(first.version != second.version)
    }

    @Test func aDeletedPhotoStaysDeletedAndItsImageIsGone() async throws {
        let backend = SamplePhotoBackend()
        _ = try await backend.savePhoto(photo("a"), image: Data([1, 2]))
        try await backend.deletePhoto(id: "a")

        let listing = try await backend.listPhotos()
        #expect(listing.photos.isEmpty)
        #expect(listing.deletedIDs == ["a"])
        #expect(backend.images.isEmpty)
        await #expect(throws: PhotoBackendError.photoDeleted) {
            _ = try await backend.savePhoto(photo("a"), image: nil)
        }
    }

    @Test func aDeletedAccountHoldsNothingAndTakesNothing() async throws {
        let backend = SamplePhotoBackend()
        _ = try await backend.savePhoto(photo("a"), image: Data([1, 2]))
        try await backend.deleteAccount()

        #expect(backend.photos.isEmpty)
        #expect(backend.images.isEmpty)
        await #expect(throws: PhotoBackendError.accountDeleted) {
            _ = try await backend.savePhoto(photo("b"), image: nil)
        }
        await #expect(throws: PhotoBackendError.accountDeleted) {
            _ = try await backend.listPhotos()
        }
    }
}
