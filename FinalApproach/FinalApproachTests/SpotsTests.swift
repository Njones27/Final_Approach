import FinalApproachCore
import Foundation
import Testing
import UIKit

@testable import FinalApproach

/// Spots. The client for the spot routes, the list of spots in the
/// collection, which spot's page a posted photo is shown on, and the photos
/// a spot's page holds.
@MainActor
final class SpotsTests {
    private let base = URL(string: "https://api.example.test")!
    private let posted = Date(timeIntervalSince1970: 1_800_000_000)
    private let directory: URL
    private let store: FilePhotoStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "final-approach-spots-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FilePhotoStore(directory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func json(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    /// A photo taken at the sample south approach spot. Its spot shows
    /// unless it is made private.
    private func photo(
        _ id: String = "imported-1",
        isPrivate: Bool = false,
        isBlocked: Bool = false,
        spotID: String? = "atl-south-approach"
    ) -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: "Boeing 737-800",
            registration: "N8642E",
            isRegistrationBlocked: isBlocked,
            airline: "Southwest Airlines",
            activity: "",
            loggedAt: posted,
            captureCoordinate: Coordinate(latitude: 33.6220, longitude: -84.3995),
            spotID: spotID,
            isLocationUndisclosed: isPrivate,
            status: .logged
        )
    }

    private var southApproach: SpotShowing {
        SpotShowing(spotID: "atl-south-approach", aircraftType: "Boeing 737-800", airline: "Southwest Airlines")
    }

    private func tinyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func tinyJPEG() throws -> Data {
        try #require(tinyImage().jpegData(compressionQuality: 0.8))
    }

    private func standing(votes: Int = 0, score: Int? = nil) -> PostStanding {
        PostStanding(
            postedAt: posted,
            closesAt: posted.addingTimeInterval(72 * 3600),
            voteCount: votes,
            finalScore: score
        )
    }

    // MARK: The client for the spot routes

    private func spotClient(_ transport: ScriptedTransport) -> HTTPSpotBackend {
        HTTPSpotBackend(baseURL: base, transport: transport, accessToken: { "token-1" })
    }

    private func postClient(_ transport: ScriptedTransport) -> HTTPPostBackend {
        HTTPPostBackend(baseURL: base, transport: transport, accessToken: { "token-1" })
    }

    private func spotAnswer(_ id: String, latitude: Double, notes: Bool) -> [String: Any] {
        var answer: [String: Any] = [
            "id": id,
            "name": "South approach",
            "summary": "Arrivals pass low from the east.",
            "latitude": latitude,
            "longitude": -84.399,
        ]
        if notes {
            answer["accessNotes"] = "Park on the gravel."
            answer["localRules"] = "Keep the gate clear."
            answer["runwayNotes"] = "Looks at the south runways."
        }
        return answer
    }

    private func photoAnswer(_ id: String, score: Int, type: String? = nil, airline: String? = nil) -> [String: Any] {
        var answer: [String: Any] = [
            "id": id,
            "imageURL": "https://images.example.test/\(id)?signature=abc",
            "score": score,
        ]
        if let type {
            answer["aircraftType"] = type
        }
        if let airline {
            answer["airline"] = airline
        }
        return answer
    }

    @Test func theListOfSpotsIsReadAsTheSignedInUser() async throws {
        let atlanta: [String: Any] = [
            "code": "ATL",
            "city": "Atlanta",
            "latitude": 33.6407,
            "longitude": -84.4277,
            "spots": [
                spotAnswer("atl-south-approach", latitude: 33.6215, notes: true),
                spotAnswer("atl-no-notes", latitude: 33.63, notes: false),
                // A spot that is not a real place cannot go on the map.
                spotAnswer("atl-nowhere", latitude: 133, notes: false),
            ],
        ]
        let transport = ScriptedTransport([.init(body: try json(["airports": [atlanta]]))])

        let airports = try await spotClient(transport).airports()

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/spots")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(airports.count == 1)
        let airport = try #require(airports.first)
        #expect(airport.id == "ATL")
        #expect(airport.displayName == "Atlanta, ATL")
        let ids = airport.spots.map { $0.id }
        #expect(ids == ["atl-south-approach", "atl-no-notes"])
        let first = try #require(airport.spots.first)
        #expect(first.name == "South approach")
        #expect(first.accessNotes == "Park on the gravel.")
        #expect(first.localRules == "Keep the gate clear.")
        #expect(first.runwayNotes == "Looks at the south runways.")
        let second = try #require(airport.spots.last)
        #expect(second.accessNotes.isEmpty)
    }

    @Test func aSpotsPhotosComeWithTheirGradeAndWhatTheOwnerShows() async throws {
        let transport = ScriptedTransport([
            .init(body: try json([
                "photos": [
                    photoAnswer("post-1", score: 91, type: "Boeing VC-25A", airline: "US Air Force"),
                    photoAnswer("post-2", score: 140),
                ],
                "imageLinkExpiresInSeconds": 300,
            ])),
        ])

        let photos = try await spotClient(transport).photos(atSpotID: "atl-south-approach")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/spots/atl-south-approach/photos")
        #expect(photos.count == 2)
        let best = try #require(photos.first)
        #expect(best.id == "post-1")
        #expect(best.imageURL.absoluteString == "https://images.example.test/post-1?signature=abc")
        #expect(best.score == 91)
        #expect(best.aircraftType == "Boeing VC-25A")
        #expect(best.airline == "US Air Force")
        // A photo whose owner shows no aircraft has none, and a grade is
        // kept on the scale.
        let other = try #require(photos.last)
        #expect(other.aircraftType == nil)
        #expect(other.airline == nil)
        #expect(other.score == 100)
    }

    @Test func aSpotThatIsNotListedHasNoPage() async throws {
        let transport = ScriptedTransport([
            .init(status: 404, body: try json(["message": "This spot is not listed.", "code": "unknownSpot"])),
        ])

        await #expect(throws: PhotoBackendError.unknownSpot) {
            _ = try await self.spotClient(transport).photos(atSpotID: "gone")
        }
    }

    @Test func anImageIsFetchedWithNoTokenAndALinkThatRanOutGivesNone() async throws {
        let link = try #require(URL(string: "https://images.example.test/post-1?signature=abc"))
        let transport = ScriptedTransport([.init(body: Data([1, 2, 3])), .init(status: 403)])
        let client = spotClient(transport)

        let image = try await client.image(from: link)
        let expired = try await client.image(from: link)

        #expect(image == Data([1, 2, 3]))
        #expect(expired == nil)
        let request = try #require(transport.requests.first)
        // The link carries its own permission.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: The client for showing a photo at a spot

    @Test func showingAPhotoSendsTheSpotAndTheWordsBesideItAndNothingElse() async throws {
        let transport = ScriptedTransport([
            .init(body: try json([
                "photoID": "imported-1",
                "shownAt": ["spotID": "atl-south-approach", "aircraftType": "Boeing 737-800"],
            ])),
        ])
        let showing = SpotShowing(spotID: "atl-south-approach", aircraftType: "Boeing 737-800")

        let kept = try await postClient(transport).show(photoID: "imported-1", at: showing)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api.example.test/posts/imported-1/spot")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        let body = try #require(request.httpBody)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: String]
        // No position and no registration is sent, and an airline that is
        // not shown is left out.
        #expect(sent == ["spotID": "atl-south-approach", "aircraftType": "Boeing 737-800"])
        #expect(kept == showing)
    }

    @Test func anAnswerAboutAnotherPhotoIsNotTrusted() async throws {
        let transport = ScriptedTransport([
            .init(body: try json(["photoID": "imported-2", "shownAt": ["spotID": "atl-south-approach"]])),
        ])

        await #expect(throws: PhotoBackendError.unreadableAnswer) {
            _ = try await self.postClient(transport).show(
                photoID: "imported-1",
                at: SpotShowing(spotID: "atl-south-approach")
            )
        }
    }

    @Test func aPhotoThatIsNotPostedOrASpotThatIsNotListedIsRefused() async throws {
        let transport = ScriptedTransport([
            .init(status: 409, body: try json(["message": "Post the photo first.", "code": "notPosted"])),
            .init(status: 404, body: try json(["message": "This spot is not listed.", "code": "unknownSpot"])),
        ])
        let showing = SpotShowing(spotID: "atl-south-approach")

        await #expect(throws: PhotoBackendError.notPosted) {
            _ = try await self.postClient(transport).show(photoID: "imported-1", at: showing)
        }
        await #expect(throws: PhotoBackendError.unknownSpot) {
            _ = try await self.postClient(transport).show(photoID: "imported-1", at: showing)
        }
    }

    @Test func takingAPhotoOffASpotSendsOnlyItsID() async throws {
        let transport = ScriptedTransport([.init(status: 204)])

        try await postClient(transport).hide(photoID: "imported-1")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.example.test/posts/imported-1/spot")
        #expect(request.httpBody == nil)
    }

    @Test func aListingSaysWhichPageEachPhotoIsOn() async throws {
        let shown: [String: Any] = [
            "photoID": "imported-1",
            "postedAt": "2027-01-15T08:00:00.000Z",
            "closesAt": "2027-01-18T08:00:00.000Z",
            "voteCount": 6,
            "status": "final",
            "score": 74,
            "shownAt": ["spotID": "atl-south-approach", "airline": "Southwest Airlines"],
        ]
        let notShown: [String: Any] = [
            "photoID": "imported-2",
            "postedAt": "2027-01-15T08:00:00.000Z",
            "closesAt": "2027-01-18T08:00:00.000Z",
            "voteCount": 0,
            "status": "voting",
        ]
        let transport = ScriptedTransport([.init(body: try json(["posts": [shown, notShown], "minVotes": 5]))])

        let listing = try await postClient(transport).listPosts()

        #expect(listing.standings.count == 2)
        #expect(listing.showings == [
            "imported-1": SpotShowing(spotID: "atl-south-approach", airline: "Southwest Airlines"),
        ])
    }

    // MARK: Which page a photo may go on

    @Test func aPhotoWithItsSpotShowingMayGoOnThatSpotsPage() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: photo()) == southApproach)
    }

    @Test func aPrivatePhotoGoesOnNoPage() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: photo(isPrivate: true)) == nil)
        // Its owner still sees which spot it was taken from.
        #expect(model.listedSpot(for: photo(isPrivate: true))?.id == "atl-south-approach")
    }

    @Test func aSamplePhotoGoesOnNoPage() throws {
        let model = SampleData.model()
        let sample = try #require(model.photo(id: "b737-n823ak"))

        #expect(model.spotShowing(for: sample) == nil)
    }

    @Test func aBlockedAircraftShowsNoTypeAndNoAirline() {
        let model = SampleData.model()

        #expect(model.spotShowing(for: photo(isBlocked: true)) == SpotShowing(spotID: "atl-south-approach"))
    }

    @Test func aLineTheBackendWouldRefuseIsLeftOut() {
        let model = SampleData.model()
        let long = SpottedPhoto(
            id: "imported-1",
            imageName: nil,
            aircraftType: String(repeating: "a", count: model.shownTextMaxLength + 1),
            registration: "",
            airline: "  ",
            activity: "",
            spotID: "atl-south-approach",
            status: .logged
        )

        #expect(model.spotShowing(for: long) == SpotShowing(spotID: "atl-south-approach"))
    }

    @Test func aPhotoLoggedBeforeItsSpotWasListedFindsItByWhereItWasTaken() {
        // A build with a backend starts with no spots.
        let model = SampleData.model(airports: [])
        #expect(model.airports.isEmpty)
        #expect(model.listedSpot(for: photo(spotID: nil)) == nil)
        #expect(model.spotShowing(for: photo(spotID: nil)) == nil)

        model.takeSpotCatalog(SampleData.airports)

        #expect(model.listedSpot(for: photo(spotID: nil))?.id == "atl-south-approach")
        #expect(model.spotShowing(for: photo(spotID: nil)) == southApproach)
    }

    @Test func aSpotThatIsNoLongerListedGivesWayToTheNearestOne() {
        let model = SampleData.model()

        #expect(model.listedSpot(for: photo(spotID: "atl-closed-spot"))?.id == "atl-south-approach")
    }

    @Test func onlyAPostedPhotoIsOnAPage() {
        let model = SampleData.model()
        model.add(photo("imported-1"))
        model.add(photo("imported-2"))

        model.takePostListing(PostListing(
            standings: ["imported-1": standing()],
            showings: ["imported-1": southApproach, "imported-2": southApproach],
            minimumVotes: 5
        ))

        #expect(model.spotShowings == ["imported-1": southApproach])

        // A page set for a photo with no post is not kept.
        model.takeSpotShowing(southApproach, forPhotoID: "imported-2")
        #expect(model.spotShowings == ["imported-1": southApproach])
    }

    @Test func aListingThatNamesNoPageTakesThePhotoOffItsPage() {
        let model = SampleData.model()
        model.add(photo())
        model.takePostListing(PostListing(
            standings: ["imported-1": standing()],
            showings: ["imported-1": southApproach],
            minimumVotes: 5
        ))

        model.takePostListing(PostListing(standings: ["imported-1": standing()], minimumVotes: 5))

        #expect(model.spotShowings.isEmpty)
    }

    @Test func deletingAPhotoOrTheAccountForgetsItsPage() {
        let model = SampleData.model()
        model.add(photo("imported-1"))
        model.add(photo("imported-2"))
        model.takePostListing(PostListing(
            standings: ["imported-1": standing(), "imported-2": standing()],
            showings: ["imported-1": southApproach, "imported-2": southApproach],
            minimumVotes: 5
        ))

        model.deletePhoto(id: "imported-1")
        #expect(model.spotShowings == ["imported-2": southApproach])

        model.deleteAccountAndPhotos()
        #expect(model.spotShowings.isEmpty)
    }

    @Test func aPageIsStillThereWhenTheAppReopens() {
        let model = SampleData.model(store: store)
        model.add(photo(), image: tinyImage())
        model.takePostListing(PostListing(
            standings: ["imported-1": standing(votes: 6, score: 74)],
            showings: ["imported-1": southApproach],
            minimumVotes: 5
        ))

        let reopened = SampleData.model(store: store)

        #expect(reopened.spotShowings == ["imported-1": southApproach])
    }

    @Test func aLibrarySavedBeforeSpotPagesExistedStillOpens() throws {
        let old = Data(#"{"photos":[],"removedSampleIDs":[]}"#.utf8)

        let library = try JSONDecoder().decode(StoredLibrary.self, from: old)

        #expect(library.spotShowings == nil)
    }

    // MARK: Showing a posted photo at its spot

    private func appleToken(for userID: String = "apple-user-1") -> String {
        let payload = Data(#"{"sub":"\#(userID)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    private func signedInSession() async throws -> AccountSession {
        let session = AccountSession(identity: SampleIdentityService(), store: MemorySessionStore())
        try await session.signIn(identityToken: appleToken())
        return session
    }

    private struct Rig {
        let sync: SyncCoordinator
        let photos: SamplePhotoBackend
        let posts: SamplePostBackend
    }

    /// A coordinator on in-memory backends, signed in.
    private func makeRig() async throws -> Rig {
        let photos = SamplePhotoBackend()
        let posted = self.posted
        let posts = SamplePostBackend(photos: photos, now: { posted })
        let sync = SyncCoordinator(
            session: try await signedInSession(),
            backend: photos,
            posts: posts,
            pacing: SyncPacing(),
            sleep: { _ in }
        )
        return Rig(sync: sync, photos: photos, posts: posts)
    }

    @Test func postingAPhotoWithItsSpotShowingPutsItOnTheSpotsPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(rig.posts.showings == ["imported-1": southApproach])
        #expect(phone.spotShowings == ["imported-1": southApproach])
    }

    @Test func postingAPrivatePhotoPutsItOnNoPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(isPrivate: true), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(asked == .cannotShow)
        #expect(rig.posts.showCount == 0)
        #expect(phone.spotShowings.isEmpty)
    }

    @Test func aPostStandsWhenItsPageCouldNotBeReached() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())
        rig.posts.nextShowFailure = .unavailable(status: 503)

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(phone.postStandings["imported-1"] != nil)
        #expect(phone.spotShowings.isEmpty)

        // A sync puts nothing on a page by itself. The owner asks again.
        await rig.sync.sync(on: phone)
        #expect(rig.posts.showCount == 0)

        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)
        #expect(asked == .done)
        #expect(phone.spotShowings == ["imported-1": southApproach])
    }

    @Test func theOwnerCanTakeAPhotoOffItsPageAndPutItBack() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)

        let takenOff = await rig.sync.takeOffSpot(photoID: "imported-1", on: phone)

        #expect(takenOff == .done)
        #expect(rig.posts.showings.isEmpty)
        #expect(phone.spotShowings.isEmpty)
        // The post and its standing stay.
        #expect(phone.postStandings["imported-1"] != nil)

        // It stays off through a sync, until the owner puts it back.
        await rig.sync.sync(on: phone)
        #expect(rig.posts.showings.isEmpty)

        let putBack = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)
        #expect(putBack == .done)
        #expect(rig.posts.showings == ["imported-1": southApproach])
    }

    @Test func aPhotoThatIsNotPostedGoesOnNoPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())

        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(asked == .cannotShow)
        #expect(rig.posts.showCount == 0)
    }

    @Test func aPhotoTakenAwayFromEverySpotGoesOnNoPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model(airports: [])
        phone.add(photo(), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(asked == .spotNotListed)
        #expect(rig.posts.showCount == 0)
    }

    @Test func aSpotTheBackendNoLongerListsTakesNoPhoto() async throws {
        let rig = try await makeRig()
        rig.posts.listedSpotIDs = ["atl-north-deck"]
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        let asked = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        #expect(asked == .spotNotListed)
        #expect(phone.spotShowings.isEmpty)
    }

    @Test func nothingIsShownWhileNoOneIsSignedIn() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)
        await rig.sync.signOut()

        let shown = await rig.sync.showAtSpot(photoID: "imported-1", on: phone)
        let takenOff = await rig.sync.takeOffSpot(photoID: "imported-1", on: phone)

        #expect(shown == .signInNeeded)
        #expect(takenOff == .signInNeeded)
        #expect(rig.posts.showings == ["imported-1": southApproach])
    }

    @Test func anEditToTheAircraftReachesItsPage() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)

        phone.updateDetails(
            forPhotoID: "imported-1",
            aircraftType: "Boeing 737-700",
            registration: nil,
            airline: ""
        )
        await rig.sync.sync(on: phone)

        let wanted = SpotShowing(spotID: "atl-south-approach", aircraftType: "Boeing 737-700")
        #expect(rig.posts.showings == ["imported-1": wanted])
        #expect(phone.spotShowings == ["imported-1": wanted])

        // A sync with nothing new sends nothing more.
        let sent = rig.posts.showCount
        await rig.sync.sync(on: phone)
        #expect(rig.posts.showCount == sent)
    }

    @Test func aPrivatePhotoFoundOnAPageIsTakenOff() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(photo(isPrivate: true), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)
        // The backend holds a page for it, as a mistake elsewhere could
        // leave one.
        _ = try await rig.posts.show(photoID: "imported-1", at: southApproach)

        await rig.sync.sync(on: phone)

        #expect(rig.posts.showings.isEmpty)
        #expect(phone.spotShowings.isEmpty)
    }

    // MARK: The spots model

    private func shownPhoto(_ id: String, score: Int) throws -> SampleSpotBackend.Photo {
        SampleSpotBackend.Photo(
            id: id,
            image: try tinyJPEG(),
            score: score,
            aircraftType: "Boeing 737-800",
            airline: "Southwest Airlines"
        )
    }

    /// A backend that lists the sample spots, with two photos on one page.
    private func spotBackend() throws -> SampleSpotBackend {
        SampleSpotBackend(
            airports: SampleData.airports,
            photos: [
                "atl-south-approach": [
                    try shownPhoto("post-low", score: 61),
                    try shownPhoto("post-high", score: 88),
                ],
            ]
        )
    }

    @Test func theListOfSpotsReachesTheCollection() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])
        #expect(spots.phase == .idle)

        await spots.refresh(on: model)

        #expect(spots.phase == .loaded)
        #expect(model.airports == SampleData.airports)
        #expect(model.spot(id: "atl-south-approach")?.name == "South approach")
    }

    @Test func noSpotsAreAskedForWhileNoOneIsSignedIn() async throws {
        let backend = try spotBackend()
        let session = AccountSession(identity: SampleIdentityService(), store: MemorySessionStore())
        let spots = SpotsModel(session: session, backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])

        await spots.refresh(on: model)
        await spots.loadPhotos(atSpotID: "atl-south-approach")

        #expect(spots.phase == .signInNeeded)
        #expect(backend.catalogCount == 0)
        #expect(backend.pageCounts.isEmpty)
        #expect(spots.pages.isEmpty)
        #expect(model.airports.isEmpty)
    }

    @Test func aBuildWithNoBackendShowsItsSpotsWithNoSignIn() async throws {
        let backend = try spotBackend()
        let session = AccountSession(identity: nil, store: MemorySessionStore())
        let spots = SpotsModel(session: session, backend: backend, needsSignIn: false)
        let model = SampleData.model()

        await spots.refresh(on: model)
        await spots.loadPhotos(atSpotID: "atl-south-approach")

        #expect(spots.phase == .loaded)
        #expect(spots.pages["atl-south-approach"]?.photos.count == 2)
    }

    @Test func aListThatCannotBeFetchedLeavesTheOneInHand() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])
        await spots.refresh(on: model)

        backend.catalogFailure = .unavailable(status: 503)
        await spots.refresh(on: model)

        #expect(spots.phase == .loaded)
        #expect(model.airports == SampleData.airports)
    }

    @Test func aFirstListThatCannotBeFetchedSaysSoAndIsTriedAgain() async throws {
        let backend = try spotBackend()
        backend.catalogFailure = .unavailable(status: 503)
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])

        await spots.refresh(on: model)
        #expect(spots.phase == .couldNotLoad)
        #expect(model.airports.isEmpty)

        backend.catalogFailure = nil
        await spots.refresh(on: model)
        #expect(spots.phase == .loaded)
        #expect(model.airports == SampleData.airports)
    }

    @Test func aSpotAddedOnTheBackendShowsUpOnTheNextRefresh() async throws {
        let backend = SampleSpotBackend(airports: [])
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])
        await spots.refresh(on: model)
        #expect(spots.phase == .loaded)
        #expect(model.airports.isEmpty)

        backend.list(SampleData.airports)
        await spots.refresh(on: model)

        #expect(model.airports == SampleData.airports)
    }

    @Test func aSpotsPhotosComeBestFirst() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)

        await spots.loadPhotos(atSpotID: "atl-south-approach")
        await spots.loadPhotos(atSpotID: "atl-west-road")

        let page = try #require(spots.pages["atl-south-approach"])
        #expect(page.phase == .loaded)
        let ids = page.photos.map { $0.id }
        #expect(ids == ["post-high", "post-low"])
        let best = try #require(page.photos.first)
        #expect(best.score == 88)
        #expect(best.aircraftType == "Boeing 737-800")
        // A spot nobody has shown a photo at has an empty page.
        #expect(spots.pages["atl-west-road"] == SpotsModel.Page(phase: .loaded))
    }

    @Test func photosThatCannotBeLoadedLeaveTheOnesInHand() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        await spots.loadPhotos(atSpotID: "atl-south-approach")

        backend.pageFailure = .unavailable(status: 503)
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        await spots.loadPhotos(atSpotID: "atl-north-deck")

        let page = try #require(spots.pages["atl-south-approach"])
        #expect(page.phase == .couldNotLoad)
        #expect(page.photos.count == 2)
        #expect(spots.pages["atl-north-deck"] == SpotsModel.Page(phase: .couldNotLoad))
    }

    @Test func aSmallCopyOfAPhotoIsKeptOnlyWhileItIsOnAPage() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        let page = try #require(spots.pages["atl-south-approach"])
        let best = try #require(page.photos.first)

        let image = await spots.thumbnail(for: best)

        #expect(image != nil)
        #expect(spots.hasThumbnail(forPhotoID: "post-high"))

        // Its owner deletes it, and the page is asked for again.
        backend.remove(photoID: "post-high")
        await spots.loadPhotos(atSpotID: "atl-south-approach")

        #expect(!spots.hasThumbnail(forPhotoID: "post-high"))
        #expect(spots.pages["atl-south-approach"]?.photos.count == 1)
    }

    @Test func aPhotoWhoseLinkRanOutHasNoImage() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let link = try #require(URL(string: "https://images.example.test/gone"))
        let gone = SpotPhoto(id: "gone", imageURL: link, score: 70)

        let image = await spots.thumbnail(for: gone)

        #expect(image == nil)
        #expect(!spots.hasThumbnail(forPhotoID: "gone"))
    }

    @Test func deletingAPhotoClearsTheCopiesOfSpotPhotos() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model()
        spots.follow(model)
        model.add(photo())
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        let page = try #require(spots.pages["atl-south-approach"])
        let best = try #require(page.photos.first)
        _ = await spots.thumbnail(for: best)
        #expect(spots.hasThumbnail(forPhotoID: "post-high"))

        // One of the photos on a page may be the user's own, so a delete
        // leaves no copy behind.
        model.deletePhoto(id: "imported-1")

        #expect(spots.pages.isEmpty)
        #expect(!spots.hasThumbnail(forPhotoID: "post-high"))
    }

    @Test func deletingTheAccountClearsTheCopiesOfSpotPhotos() async throws {
        let backend = try spotBackend()
        let spots = SpotsModel(session: try await signedInSession(), backend: backend, needsSignIn: true)
        let model = SampleData.model()
        spots.follow(model)
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        let page = try #require(spots.pages["atl-south-approach"])
        let best = try #require(page.photos.first)
        _ = await spots.thumbnail(for: best)

        model.deleteAccountAndPhotos()

        #expect(spots.pages.isEmpty)
        #expect(!spots.hasThumbnail(forPhotoID: "post-high"))
    }

    @Test func signingOutForgetsThePhotosAndKeepsTheSpots() async throws {
        let backend = try spotBackend()
        let session = try await signedInSession()
        let spots = SpotsModel(session: session, backend: backend, needsSignIn: true)
        let model = SampleData.model(airports: [])
        await spots.refresh(on: model)
        await spots.loadPhotos(atSpotID: "atl-south-approach")
        #expect(spots.pages.count == 1)

        await session.signOut()
        await spots.refresh(on: model)

        #expect(spots.phase == .signInNeeded)
        #expect(spots.pages.isEmpty)
        // The list stays, so a photo logged while signed out still finds
        // its spot.
        #expect(model.airports == SampleData.airports)
    }

    @Test func aLargeImageIsMadeSmallAndASmallOneIsLeftAlone() {
        #expect(SpotsModel.fitted(CGSize(width: 6000, height: 4000), within: 1200) == CGSize(width: 1200, height: 800))
        #expect(SpotsModel.fitted(CGSize(width: 3000, height: 4500), within: 1200) == CGSize(width: 800, height: 1200))
        #expect(SpotsModel.fitted(CGSize(width: 900, height: 600), within: 1200) == CGSize(width: 900, height: 600))
    }

    // MARK: Wording

    @Test func theWarningBeforeAPostSaysWhereThePhotoWillBeSeen() {
        let plain = PhotoDetailView.postWarning(spotName: nil, showsAircraft: true)
        let shown = PhotoDetailView.postWarning(spotName: "South approach", showsAircraft: true)
        let blocked = PhotoDetailView.postWarning(spotName: "South approach", showsAircraft: false)

        #expect(plain == "Voters see the photo and nothing else. They do not see your name or where it was taken. "
            + "A post cannot be taken back, but deleting the photo removes it.")
        #expect(shown.contains("it also goes on the page for South approach with its grade, aircraft type, and airline."))
        #expect(shown.contains("Your name and the registration are never shown there."))
        // A blocked aircraft is not named on the page, so the warning does
        // not say it is.
        #expect(blocked.contains("the page for South approach with its grade."))
        #expect(!blocked.contains("aircraft type"))
    }

    @Test func theOwnerIsToldWhetherAPhotoIsOnItsPageYet() {
        #expect(PhotoDetailView.shownLine(spotName: "South approach", isGraded: true)
            == "Shown on the page for South approach.")
        #expect(PhotoDetailView.shownLine(spotName: "South approach", isGraded: false)
            == "It goes on the page for South approach once it is graded.")
        #expect(PhotoDetailView.shownLine(spotName: nil, isGraded: true) == "Shown on its spot's page.")
    }

    @Test func theOfferSaysWhatOtherPeopleWillSee() {
        let offer = PhotoDetailView.offerLine(spotName: "South approach", showsAircraft: true)
        let blocked = PhotoDetailView.offerLine(spotName: "South approach", showsAircraft: false)

        #expect(offer.contains("its grade, aircraft type, and airline"))
        #expect(offer.contains("They never see your name or the registration."))
        #expect(!blocked.contains("aircraft type"))
    }

    @Test func everyOutcomeOfChangingAPageHasSomethingToSay() {
        let outcomes: [SpotShowOutcome] = [.done, .signInNeeded, .cannotShow, .spotNotListed, .couldNotChange]
        for outcome in outcomes {
            #expect(!PhotoDetailView.message(for: outcome).isEmpty)
        }
    }

    @Test func aSpotsPageLeavesOutANoteWithNothingWritten() throws {
        let full = try #require(SampleData.airports.first?.spots.first)
        let bare = Spot(id: "bare", name: "Bare", summary: "Nothing written.", latitude: 33.6, longitude: -84.4)

        let titles = SpotPageView.notes(for: full).map { $0.title }
        #expect(titles == ["Getting there", "Local rules", "Runways"])
        #expect(SpotPageView.notes(for: bare).isEmpty)
    }

    @Test func aPhotoOnAPageIsDescribedByWhatItsOwnerShows() throws {
        let link = try #require(URL(string: "https://images.example.test/post-1"))
        let named = SpotPhoto(
            id: "post-1",
            imageURL: link,
            score: 80,
            aircraftType: "Boeing 737-800",
            airline: "Southwest Airlines"
        )
        let unnamed = SpotPhoto(id: "post-2", imageURL: link, score: 80)

        #expect(SpotPageView.imageDescription(for: named, spotName: "South approach")
            == "Southwest Airlines Boeing 737-800, taken from South approach")
        #expect(SpotPageView.imageDescription(for: unnamed, spotName: "South approach")
            == "A photo taken from South approach")
    }
}
