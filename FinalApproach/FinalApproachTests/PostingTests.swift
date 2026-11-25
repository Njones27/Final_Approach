import FinalApproachCore
import Foundation
import Testing
import UIKit

@testable import FinalApproach

/// Posting a photo for votes. The client for the post routes, where a
/// posted photo stands in the collection, and the order a post is made in.
@MainActor
final class PostingTests {
    private let base = URL(string: "https://api.example.test")!
    private let posted = Date(timeIntervalSince1970: 1_800_000_000)
    private let directory: URL
    private let store: FilePhotoStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "final-approach-posting-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FilePhotoStore(directory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    private func loggedPhoto(_ id: String = "imported-1") -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: "Boeing 737-800",
            registration: "N8642E",
            airline: "Southwest Airlines",
            activity: "",
            loggedAt: posted,
            captureCoordinate: Coordinate(latitude: 33.6220, longitude: -84.3995),
            spotID: "atl-south-approach",
            isLocationUndisclosed: true,
            status: .logged
        )
    }

    private func tinyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func standing(votes: Int = 0, score: Int? = nil) -> PostStanding {
        PostStanding(
            postedAt: posted,
            closesAt: posted.addingTimeInterval(72 * 3600),
            voteCount: votes,
            finalScore: score
        )
    }

    /// One post as the backend sends it.
    private func postAnswer(
        _ photoID: String = "imported-1",
        votes: Int = 0,
        status: String = "voting",
        score: Int? = nil
    ) -> [String: Any] {
        var answer: [String: Any] = [
            "photoID": photoID,
            "postedAt": "2027-01-15T08:00:00.000Z",
            "closesAt": "2027-01-18T08:00:00.000Z",
            "voteCount": votes,
            "status": status,
        ]
        if let score {
            answer["score"] = score
        }
        return answer
    }

    private func client(_ transport: ScriptedTransport) -> HTTPPostBackend {
        HTTPPostBackend(
            baseURL: base,
            transport: transport,
            placeGrid: SampleData.placeGrid,
            accessToken: { "token-1" }
        )
    }

    // MARK: The client

    @Test func postingSendsOnlyThePhotosIDAsTheSignedInUser() async throws {
        let transport = ScriptedTransport([.init(body: try json(postAnswer()))])

        let result = try await client(transport).post(photoID: "imported-1")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api.example.test/posts/imported-1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        // Nothing about the photo is sent again, so no location can be.
        #expect(request.httpBody == nil)
        #expect(result.voteCount == 0)
        #expect(result.finalScore == nil)
        #expect(result.closesAt.timeIntervalSince(result.postedAt) == 72 * 3600)
    }

    @Test func aFinalPostCarriesItsScore() async throws {
        let transport = ScriptedTransport([
            .init(body: try json(postAnswer(votes: 7, status: "final", score: 81))),
        ])

        let result = try await client(transport).post(photoID: "imported-1")

        #expect(result.voteCount == 7)
        #expect(result.finalScore == 81)
    }

    @Test func anAnswerAboutAnotherPhotoIsNotTrusted() async throws {
        let transport = ScriptedTransport([.init(body: try json(postAnswer("imported-2")))])

        await #expect(throws: PhotoBackendError.unreadableAnswer) {
            _ = try await self.client(transport).post(photoID: "imported-1")
        }
    }

    @Test func aFinalAnswerWithNoScoreIsNotTrusted() async throws {
        let transport = ScriptedTransport([.init(body: try json(postAnswer(votes: 7, status: "final")))])

        await #expect(throws: PhotoBackendError.unreadableAnswer) {
            _ = try await self.client(transport).post(photoID: "imported-1")
        }
    }

    @Test func aRefusedPostBecomesTheErrorTheAppActsOn() async throws {
        let transport = ScriptedTransport([
            .init(status: 409, body: try json(["message": "Save the photo first.", "code": "photoNotSaved"])),
            .init(status: 422, body: try json(["message": "The image has a location.", "code": "imageHasLocation"])),
        ])

        await #expect(throws: PhotoBackendError.photoNotSaved) {
            _ = try await self.client(transport).post(photoID: "imported-1")
        }
        await #expect(throws: PhotoBackendError.imageHasLocation) {
            _ = try await self.client(transport).post(photoID: "imported-1")
        }
    }

    @Test func aListingFollowsEveryPageAndReadsTheMinimum() async throws {
        let transport = ScriptedTransport([
            .init(body: try json([
                "posts": [postAnswer("imported-1", votes: 2)],
                "minVotes": 5,
                "nextAfter": "imported-1",
            ])),
            .init(body: try json([
                "posts": [postAnswer("imported-2", votes: 9, status: "final", score: 64)],
                "minVotes": 5,
            ])),
        ])

        let listing = try await client(transport).listPosts()

        #expect(listing.minimumVotes == 5)
        #expect(listing.standings["imported-1"]?.voteCount == 2)
        #expect(listing.standings["imported-1"]?.finalScore == nil)
        #expect(listing.standings["imported-2"]?.finalScore == 64)
        #expect(transport.requests.map { $0.url?.absoluteString } == [
            "https://api.example.test/posts",
            "https://api.example.test/posts?after=imported-1",
        ])
    }

    @Test func aPostThisVersionCannotReadIsLeftOut() async throws {
        let transport = ScriptedTransport([
            .init(body: try json([
                "posts": [postAnswer("imported-1", status: "paused"), postAnswer("imported-2")],
                "minVotes": 5,
            ])),
        ])

        let listing = try await client(transport).listPosts()

        #expect(listing.standings.keys.sorted() == ["imported-2"])
    }

    // MARK: Where a posted photo stands

    @Test func aPhotoTheUserLoggedCanBePostedAndASampleCannot() throws {
        let model = SampleData.model()
        model.add(loggedPhoto())

        #expect(model.canBePosted(loggedPhoto()))
        #expect(model.progress(for: loggedPhoto()) == .logged)
        let sample = try #require(model.photo(id: "b737-n823ak"))
        #expect(!model.canBePosted(sample))
    }

    @Test func aPostedPhotoShowsItsVotesAndTheTimeLeft() {
        let model = SampleData.model()
        model.add(loggedPhoto())
        model.takePostStanding(standing(votes: 2), forPhotoID: "imported-1")

        let early = model.progress(for: loggedPhoto(), at: posted.addingTimeInterval(3600))
        #expect(early == .voting(votesIn: 2, votesNeeded: 3, hoursLeft: 71))
        // Past the window and short of votes, it stays open.
        let late = model.progress(for: loggedPhoto(), at: posted.addingTimeInterval(80 * 3600))
        #expect(late == .voting(votesIn: 2, votesNeeded: 3, hoursLeft: 0))
        #expect(model.finalScore(for: loggedPhoto()) == nil)
        #expect(model.tier(for: loggedPhoto()) == .logged)
        #expect(!model.canBePosted(loggedPhoto()))
    }

    @Test func theVotesAloneSetTheGradeOfAPostedPhoto() {
        let model = SampleData.model()
        model.add(loggedPhoto())
        model.takePostStanding(standing(votes: 8, score: 81), forPhotoID: "imported-1")

        #expect(model.progress(for: loggedPhoto()) == .graded(score: 81, voteCount: 8))
        #expect(model.finalScore(for: loggedPhoto()) == 81)
        #expect(model.tier(for: loggedPhoto()) == .gold)
        #expect(model.provisionalScore(for: loggedPhoto()) == nil)
    }

    @Test func theBackendsMinimumWinsOverTheOneInTheApp() {
        let model = SampleData.model()
        model.add(loggedPhoto())
        #expect(model.minimumVotes == 5)

        model.takePostListing(PostListing(standings: ["imported-1": standing(votes: 2)], minimumVotes: 8))

        #expect(model.minimumVotes == 8)
        #expect(model.progress(for: loggedPhoto(), at: posted) == .voting(votesIn: 2, votesNeeded: 6, hoursLeft: 72))
    }

    @Test func aListingReplacesWhatWasHeardBefore() {
        let model = SampleData.model()
        model.add(loggedPhoto("imported-1"))
        model.add(loggedPhoto("imported-2"))
        model.takePostStanding(standing(), forPhotoID: "imported-1")

        model.takePostListing(PostListing(
            standings: ["imported-2": standing(votes: 1), "someone-elses": standing()],
            minimumVotes: 5
        ))

        // A photo the backend lists no post for is not posted.
        #expect(model.progress(for: loggedPhoto("imported-1")) == .logged)
        #expect(model.postStandings.keys.sorted() == ["imported-2"])
    }

    @Test func aSamplePhotoNeverTakesAStanding() throws {
        let model = SampleData.model()
        let sample = try #require(model.photo(id: "b737-n823ak"))
        let before = model.progress(for: sample)

        model.takePostStanding(standing(votes: 1), forPhotoID: sample.id)

        #expect(model.postStandings.isEmpty)
        #expect(model.progress(for: sample) == before)
    }

    @Test func deletingAPhotoOrTheAccountForgetsItsPost() {
        let model = SampleData.model()
        model.add(loggedPhoto("imported-1"))
        model.add(loggedPhoto("imported-2"))
        model.takePostStanding(standing(), forPhotoID: "imported-1")
        model.takePostStanding(standing(), forPhotoID: "imported-2")

        model.deletePhoto(id: "imported-1")
        #expect(model.postStandings.keys.sorted() == ["imported-2"])

        model.deleteAccountAndPhotos()
        #expect(model.postStandings.isEmpty)
    }

    @Test func aStandingIsStillThereWhenTheAppReopens() {
        let model = SampleData.model(store: store)
        model.add(loggedPhoto(), image: tinyImage())
        model.takePostListing(PostListing(standings: ["imported-1": standing(votes: 6, score: 74)], minimumVotes: 6))

        let reopened = SampleData.model(store: store)

        #expect(reopened.postStandings == ["imported-1": standing(votes: 6, score: 74)])
        #expect(reopened.minimumVotes == 6)
        #expect(reopened.finalScore(for: loggedPhoto()) == 74)
    }

    @Test func aLibrarySavedBeforePostingExistedStillOpens() throws {
        let old = Data(#"{"photos":[],"removedSampleIDs":[]}"#.utf8)

        let library = try JSONDecoder().decode(StoredLibrary.self, from: old)

        #expect(library.postStandings == nil)
        #expect(library.postMinimumVotes == nil)
    }

    // MARK: Posting

    private func appleToken(for userID: String = "apple-user-1") -> String {
        let payload = Data(#"{"sub":"\#(userID)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    private struct Rig {
        let sync: SyncCoordinator
        let photos: SamplePhotoBackend
        let posts: SamplePostBackend
    }

    /// A coordinator on in-memory backends, signed in unless told not to.
    private func makeRig(signedIn: Bool = true, offersPosting: Bool = true) async throws -> Rig {
        let photos = SamplePhotoBackend()
        let posted = self.posted
        let posts = SamplePostBackend(photos: photos, now: { posted })
        let session = AccountSession(identity: SampleIdentityService(), store: MemorySessionStore())
        if signedIn {
            try await session.signIn(identityToken: appleToken())
        }
        let sync = SyncCoordinator(
            session: session,
            backend: photos,
            posts: offersPosting ? posts : nil,
            pacing: SyncPacing(),
            sleep: { _ in }
        )
        return Rig(sync: sync, photos: photos, posts: posts)
    }

    @Test func postingSendsThePhotoFirstAndThenOpensItForVotes() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(loggedPhoto(), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(outcome == .posted)
        // The record and the image reached the backend before the post.
        #expect(rig.photos.photos["imported-1"] == loggedPhoto())
        #expect(rig.photos.images["imported-1"] != nil)
        #expect(phone.postStandings["imported-1"] == standing())
        #expect(!phone.canBePosted(loggedPhoto()))
    }

    @Test func aPhotoWithNoImageOnTheBackendIsNotPosted() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(loggedPhoto())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(outcome == .notSavedYet)
        #expect(phone.postStandings.isEmpty)
        #expect(phone.canBePosted(loggedPhoto()))
    }

    @Test func nothingIsPostedWhileNoOneIsSignedIn() async throws {
        let rig = try await makeRig(signedIn: false)
        let phone = SampleData.model()
        phone.add(loggedPhoto(), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(outcome == .signInNeeded)
        #expect(rig.photos.photos.isEmpty)
        #expect(phone.postStandings.isEmpty)
    }

    @Test func aBuildWithNoPostRoutesOffersNoPosting() async throws {
        let rig = try await makeRig(offersPosting: false)
        let phone = SampleData.model()
        phone.add(loggedPhoto(), image: tinyImage())

        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(!rig.sync.offersPosting)
        #expect(outcome == .signInNeeded)
        #expect(phone.postStandings.isEmpty)
    }

    @Test func aSamplePhotoOrAPostedOneIsNotPostedAgain() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(loggedPhoto(), image: tinyImage())

        let sample = await rig.sync.post(photoID: "b737-n823ak", on: phone)
        let first = await rig.sync.post(photoID: "imported-1", on: phone)
        let second = await rig.sync.post(photoID: "imported-1", on: phone)

        #expect(sample == .photoGone)
        #expect(first == .posted)
        #expect(second == .photoGone)
    }

    @Test func aSyncBringsBackWhereEachPostStands() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(loggedPhoto(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)

        // Other users vote, and the grade becomes final.
        rig.posts.setStanding(voteCount: 6, finalScore: 74, forPhotoID: "imported-1")
        await rig.sync.sync(on: phone)

        #expect(phone.progress(for: loggedPhoto()) == .graded(score: 74, voteCount: 6))
        #expect(phone.minimumVotes == 5)
    }

    @Test func deletingAPostedPhotoTakesItsPostDown() async throws {
        let rig = try await makeRig()
        let phone = SampleData.model()
        phone.add(loggedPhoto(), image: tinyImage())
        let outcome = await rig.sync.post(photoID: "imported-1", on: phone)
        #expect(outcome == .posted)

        phone.deletePhoto(id: "imported-1")
        await rig.sync.sync(on: phone)
        let listed = try await rig.posts.listPosts()

        #expect(phone.postStandings.isEmpty)
        #expect(listed.standings.isEmpty)
    }

    // MARK: Wording

    @Test func theVotingLineSaysHowManyVotesAreInAndNeverHowTheyAreGoing() {
        #expect(PhotoDetailView.votingLine(votesIn: 2, votesNeeded: 3, hoursLeft: 71)
            == "2 of 5 votes so far. The grade arrives in about 71 hours, once 5 votes are in.")
        #expect(PhotoDetailView.votingLine(votesIn: 7, votesNeeded: 0, hoursLeft: 1)
            == "7 votes so far. The grade arrives in about 1 hour.")
        #expect(PhotoDetailView.votingLine(votesIn: 4, votesNeeded: 1, hoursLeft: 0)
            == "4 of 5 votes so far. The grade arrives with 1 more.")
        #expect(PhotoDetailView.votingLine(votesIn: 1, votesNeeded: 0, hoursLeft: 0)
            == "1 vote so far. The grade arrives in a few minutes.")
    }

    @Test func everyPostOutcomeHasSomethingToSay() {
        let outcomes: [PostOutcome] = [
            .posted, .signInNeeded, .notSavedYet, .imageHasLocation, .photoGone, .couldNotPost,
        ]
        for outcome in outcomes {
            #expect(!PhotoDetailView.message(for: outcome).isEmpty)
        }
    }
}
