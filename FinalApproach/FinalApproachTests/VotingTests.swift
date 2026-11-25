import FinalApproachCore
import Foundation
import Testing
import UIKit

@testable import FinalApproach

/// A vote backend that answers from a script, for the cases the sample one
/// cannot show, such as a link to an image that ran out.
@MainActor
private final class ScriptedVoteBackend: VoteBackend {
    /// The answers to give for the queue, in order. The last one repeats.
    var queues: [VoteQueue]
    /// The images behind the links that still work.
    var images: [URL: Data]
    private(set) var queueCount = 0
    private(set) var askedLinks: [URL] = []

    init(queues: [VoteQueue], images: [URL: Data]) {
        self.queues = queues
        self.images = images
    }

    func queue() async throws -> VoteQueue {
        queueCount += 1
        if queues.count > 1 { return queues.removeFirst() }
        return queues.first ?? VoteQueue()
    }

    func image(from url: URL) async throws -> Data? {
        askedLinks.append(url)
        return images[url]
    }

    func cast(_ value: Int, onPostID postID: String) async throws {}
}

/// Voting on other people's photos. The client for the vote routes, and the
/// model that runs the Vote screen.
@MainActor
struct VotingTests {
    private let base = URL(string: "https://api.example.test")!

    private func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    private func client(_ transport: ScriptedTransport) -> HTTPVoteBackend {
        HTTPVoteBackend(baseURL: base, transport: transport, accessToken: { "token-1" })
    }

    private func link(_ name: String) -> URL {
        URL(string: "https://images.example.test/\(name)?signature=abc")!
    }

    /// The queue as the backend sends it.
    private func queueAnswer(_ postIDs: [String], scaleMax: Int = 5) -> [String: Any] {
        let posts: [[String: Any]] = postIDs.map { id in
            ["postID": id, "imageURL": link(id).absoluteString]
        }
        return ["posts": posts, "scaleMax": scaleMax, "imageLinkExpiresInSeconds": 900]
    }

    private func refusal(_ code: String) throws -> Data {
        try json(["message": "Refused.", "code": code])
    }

    private func tinyImage() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return try #require(image.pngData())
    }

    // MARK: The client

    @Test func theQueueIsAskedForAsTheSignedInUser() async throws {
        let transport = ScriptedTransport([.init(body: try json(queueAnswer(["post-a", "post-b"])))])

        let queue = try await client(transport).queue()

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.test/votes/queue")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(queue.posts == [
            VotePost(id: "post-a", imageURL: link("post-a")),
            VotePost(id: "post-b", imageURL: link("post-b")),
        ])
        #expect(queue.scaleMax == 5)
    }

    @Test func aQueueThatCannotBeReadIsAnError() async throws {
        let transport = ScriptedTransport([.init(body: Data("not json".utf8))])

        await #expect(throws: PhotoBackendError.unreadableAnswer) {
            _ = try await self.client(transport).queue()
        }
    }

    @Test func anImageIsFetchedFromItsLinkWithNoToken() async throws {
        let transport = ScriptedTransport([.init(body: Data([1, 2, 3]))])

        let data = try await client(transport).image(from: link("post-a"))

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url == link("post-a"))
        // The link carries its own permission. The user's token is not
        // sent to the image storage.
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(data == Data([1, 2, 3]))
    }

    @Test(arguments: [403, 404])
    func aLinkThatRanOutGivesNoImage(status: Int) async throws {
        let transport = ScriptedTransport([.init(status: status)])

        let data = try await client(transport).image(from: link("post-a"))

        #expect(data == nil)
    }

    @Test func imageStorageThatFailsIsAnError() async throws {
        let transport = ScriptedTransport([.init(status: 503)])

        await #expect(throws: PhotoBackendError.unavailable(status: 503)) {
            _ = try await self.client(transport).image(from: self.link("post-a"))
        }
    }

    @Test func aVoteSendsItsStarsAsTheSignedInUser() async throws {
        let transport = ScriptedTransport([.init(body: try json(["postID": "post-a", "value": 4]))])

        try await client(transport).cast(4, onPostID: "post-a")

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://api.example.test/votes/post-a")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: Int]
        #expect(sent == ["value": 4])
    }

    @Test func theBackendsRefusalsOfAVoteAreToldApart() async throws {
        let transport = ScriptedTransport([
            .init(status: 409, body: try refusal("alreadyVoted")),
            .init(status: 410, body: try refusal("votingClosed")),
            .init(status: 403, body: try refusal("ownPost")),
            .init(status: 401),
        ])

        await #expect(throws: PhotoBackendError.alreadyVoted) {
            try await self.client(transport).cast(3, onPostID: "post-a")
        }
        await #expect(throws: PhotoBackendError.votingClosed) {
            try await self.client(transport).cast(3, onPostID: "post-a")
        }
        await #expect(throws: PhotoBackendError.ownPost) {
            try await self.client(transport).cast(3, onPostID: "post-a")
        }
        await #expect(throws: PhotoBackendError.notSignedIn) {
            try await self.client(transport).cast(3, onPostID: "post-a")
        }
    }

    // MARK: The Vote screen's model

    private func appleToken(for userID: String = "apple-user-1") -> String {
        let payload = Data(#"{"sub":"\#(userID)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    private func makeSession(signedIn: Bool = true) async throws -> AccountSession {
        let session = AccountSession(identity: SampleIdentityService(), store: MemorySessionStore())
        if signedIn {
            try await session.signIn(identityToken: appleToken())
        }
        return session
    }

    private func samplePosts(_ ids: [String]) throws -> [SampleVoteBackend.Post] {
        let image = try tinyImage()
        return ids.map { SampleVoteBackend.Post(id: $0, image: image) }
    }

    private struct Rig {
        let voting: VotingModel
        let backend: SampleVoteBackend
        let session: AccountSession
    }

    /// A voting model on the sample backend, signed in unless told not to.
    private func makeRig(
        _ ids: [String] = ["post-a", "post-b", "post-c"],
        signedIn: Bool = true,
        scaleMax: Int = 5
    ) async throws -> Rig {
        let backend = SampleVoteBackend(posts: try samplePosts(ids), scaleMax: scaleMax)
        let session = try await makeSession(signedIn: signedIn)
        return Rig(voting: VotingModel(session: session, backend: backend), backend: backend, session: session)
    }

    @Test func aBuildWithNoBackendKeepsTheSampleSet() async throws {
        let session = try await makeSession()
        let voting = VotingModel(session: session, backend: nil)

        await voting.refresh()

        #expect(!voting.isLive)
        #expect(voting.phase == .idle)
        #expect(voting.ballot == nil)
    }

    @Test func aBuildThatCannotSignInKeepsTheSampleSet() async throws {
        let backend = SampleVoteBackend(posts: try samplePosts(["post-a"]))
        let session = AccountSession(identity: nil, store: MemorySessionStore())
        let voting = VotingModel(session: session, backend: backend)

        await voting.refresh()

        #expect(!voting.isLive)
        #expect(backend.queueCount == 0)
    }

    @Test func aSignedOutUserIsAskedToSignIn() async throws {
        let rig = try await makeRig(signedIn: false)

        await rig.voting.refresh()

        #expect(rig.voting.isLive)
        #expect(rig.voting.phase == .signInNeeded)
        #expect(rig.voting.ballot == nil)
        // Nothing is asked of the backend for someone who is signed out.
        #expect(rig.backend.queueCount == 0)
    }

    @Test func theFirstPhotoIsShownForAVote() async throws {
        let rig = try await makeRig()

        await rig.voting.refresh()

        #expect(rig.voting.phase == .voting)
        #expect(rig.voting.ballot?.id == "post-a")
        #expect(rig.voting.scale == 1...5)
        #expect(!rig.voting.isBusy)
        #expect(rig.backend.queueCount == 1)
    }

    @Test func comingBackToTheScreenKeepsThePhotoThatIsShowing() async throws {
        let rig = try await makeRig()
        await rig.voting.refresh()

        await rig.voting.refresh()

        #expect(rig.voting.ballot?.id == "post-a")
        #expect(rig.backend.queueCount == 1)
    }

    @Test func theBackendSetsHowManyStarsAVoteCanGive() async throws {
        let rig = try await makeRig(scaleMax: 7)

        await rig.voting.refresh()
        await rig.voting.cast(7)

        #expect(rig.voting.scale == 1...7)
        #expect(rig.backend.votes == ["post-a": 7])
    }

    @Test func aScaleTooLargeForTheScreenIsIgnored() async throws {
        let rig = try await makeRig(scaleMax: 50)

        await rig.voting.refresh()

        #expect(rig.voting.scale == 1...5)
    }

    @Test func aVoteIsCountedAndTheNextPhotoIsShown() async throws {
        let rig = try await makeRig()
        await rig.voting.refresh()

        await rig.voting.cast(4)

        #expect(rig.backend.votes == ["post-a": 4])
        #expect(rig.voting.votesCast == 1)
        #expect(rig.voting.ballot?.id == "post-b")
        #expect(rig.voting.phase == .voting)
        #expect(!rig.voting.lastVoteFailed)
    }

    @Test func aVoteOffTheScaleIsNotSent() async throws {
        let rig = try await makeRig()
        await rig.voting.refresh()

        await rig.voting.cast(0)
        await rig.voting.cast(6)

        #expect(rig.backend.votes.isEmpty)
        #expect(rig.voting.votesCast == 0)
        #expect(rig.voting.ballot?.id == "post-a")
    }

    @Test func votingOnEveryPhotoLeavesNothingToVoteOn() async throws {
        let rig = try await makeRig(["post-a", "post-b"])
        await rig.voting.refresh()

        await rig.voting.cast(5)
        await rig.voting.cast(2)

        #expect(rig.backend.votes == ["post-a": 5, "post-b": 2])
        #expect(rig.voting.votesCast == 2)
        #expect(rig.voting.phase == .empty)
        #expect(rig.voting.ballot == nil)
    }

    @Test func aPhotoPostedLaterShowsUpOnTheNextCheck() async throws {
        let rig = try await makeRig(["post-a"])
        await rig.voting.refresh()
        await rig.voting.cast(3)
        #expect(rig.voting.phase == .empty)

        let added = try samplePosts(["post-new"])
        rig.backend.add(added[0])
        await rig.voting.refresh()

        #expect(rig.voting.phase == .voting)
        #expect(rig.voting.ballot?.id == "post-new")
    }

    @Test func aSkippedPhotoGetsNoVoteAndDoesNotComeBack() async throws {
        let rig = try await makeRig(["post-a", "post-b"])
        await rig.voting.refresh()

        await rig.voting.skip()
        #expect(rig.voting.ballot?.id == "post-b")
        await rig.voting.cast(4)

        // The backend still hands out the skipped photo, because it has no
        // vote. It is not shown a second time on this visit.
        #expect(rig.backend.votes == ["post-b": 4])
        #expect(rig.voting.votesCast == 1)
        #expect(rig.voting.phase == .empty)
        #expect(rig.voting.ballot == nil)
    }

    @Test func aVoteThatDoesNotReachTheBackendKeepsThePhoto() async throws {
        let rig = try await makeRig()
        await rig.voting.refresh()
        rig.backend.nextCastFailure = .unavailable(status: 503)

        await rig.voting.cast(4)

        #expect(rig.voting.lastVoteFailed)
        #expect(rig.voting.votesCast == 0)
        #expect(rig.voting.ballot?.id == "post-a")
        #expect(rig.voting.phase == .voting)

        // The same vote goes through on the next try.
        await rig.voting.cast(4)

        #expect(!rig.voting.lastVoteFailed)
        #expect(rig.backend.votes == ["post-a": 4])
        #expect(rig.voting.ballot?.id == "post-b")
    }

    @Test(arguments: [PhotoBackendError.alreadyVoted, .votingClosed, .ownPost])
    func aVoteThatCannotCountMovesOn(refusal: PhotoBackendError) async throws {
        let rig = try await makeRig()
        await rig.voting.refresh()
        rig.backend.nextCastFailure = refusal

        await rig.voting.cast(4)

        #expect(rig.voting.votesCast == 0)
        #expect(!rig.voting.lastVoteFailed)
        #expect(rig.voting.ballot?.id == "post-b")
    }

    @Test func aSignInThatEndedAsksForANewOne() async throws {
        let rig = try await makeRig()
        await rig.voting.refresh()
        rig.backend.nextCastFailure = .notSignedIn

        await rig.voting.cast(4)

        #expect(rig.voting.phase == .signInNeeded)
        #expect(rig.voting.ballot == nil)
        #expect(rig.voting.votesCast == 0)
    }

    @Test func aBackendThatCannotBeReachedCanBeTriedAgain() async throws {
        let rig = try await makeRig()
        rig.backend.queueFailure = .unavailable(status: 503)

        await rig.voting.refresh()

        #expect(rig.voting.phase == .couldNotLoad)
        #expect(rig.voting.ballot == nil)

        rig.backend.queueFailure = nil
        await rig.voting.refresh()

        #expect(rig.voting.phase == .voting)
        #expect(rig.voting.ballot?.id == "post-a")
    }

    @Test func aPhotoThatWasTakenDownIsPassedOver() async throws {
        let rig = try await makeRig(["post-a", "post-b", "post-c"])
        await rig.voting.refresh()
        // Its owner deletes it after the queue was handed out.
        rig.backend.remove(postID: "post-b")

        await rig.voting.cast(4)

        #expect(rig.voting.ballot?.id == "post-c")
        #expect(rig.voting.phase == .voting)
    }

    @Test func aLinkThatRanOutIsAskedForAgain() async throws {
        let image = try tinyImage()
        let old = link("post-b-old")
        let new = link("post-b-new")
        let backend = ScriptedVoteBackend(
            queues: [
                VoteQueue(posts: [VotePost(id: "post-a", imageURL: link("post-a")), VotePost(id: "post-b", imageURL: old)], scaleMax: 5),
                VoteQueue(posts: [VotePost(id: "post-b", imageURL: new)], scaleMax: 5),
            ],
            // The first link to the second photo has run out.
            images: [link("post-a"): image, new: image]
        )
        let session = try await makeSession()
        let voting = VotingModel(session: session, backend: backend)
        await voting.refresh()

        await voting.cast(4)

        #expect(voting.ballot?.id == "post-b")
        #expect(backend.queueCount == 2)
        #expect(backend.askedLinks == [link("post-a"), old, new])
    }

    @Test func photosWithNoImageDoNotKeepTheSearchGoing() async throws {
        let backend = ScriptedVoteBackend(
            queues: [VoteQueue(posts: [VotePost(id: "post-a", imageURL: link("post-a"))], scaleMax: 5)],
            images: [:]
        )
        let session = try await makeSession()
        let voting = VotingModel(session: session, backend: backend)

        await voting.refresh()

        #expect(voting.phase == .empty)
        #expect(voting.ballot == nil)
        // The backend is asked twice at most in one go.
        #expect(backend.queueCount == 2)
    }

    @Test func signingOutClearsThePhotoOnTheScreen() async throws {
        let rig = try await makeRig()
        await rig.voting.refresh()
        await rig.voting.cast(4)

        await rig.session.signOut()
        await rig.voting.refresh()

        #expect(rig.voting.phase == .signInNeeded)
        #expect(rig.voting.ballot == nil)
        #expect(rig.voting.votesCast == 0)
    }

    @Test func aDifferentUserStartsOver() async throws {
        let rig = try await makeRig(["post-a", "post-b"])
        await rig.voting.refresh()
        await rig.voting.skip()
        #expect(rig.voting.ballot?.id == "post-b")

        await rig.session.signOut()
        try await rig.session.signIn(identityToken: appleToken(for: "apple-user-2"))
        await rig.voting.refresh()

        // What the first user skipped is not held against the second.
        #expect(rig.voting.phase == .voting)
        #expect(rig.voting.ballot?.id == "post-a")
        #expect(rig.voting.votesCast == 0)
    }

    // MARK: The screen's own rules

    @Test func aWidePhotoTakesTheFullWidth() {
        let height = VoteView.photoHeight(
            for: CGSize(width: 3000, height: 2000),
            in: CGSize(width: 390, height: 700)
        )

        #expect(height == 260)
    }

    @Test func aTallPhotoTakesTheFullWidthToo() {
        let screen = CGSize(width: 390, height: 700)

        let height = VoteView.photoHeight(for: CGSize(width: 2000, height: 3000), in: screen)

        #expect(height == 585)
    }

    @Test func noPhotoIsDrawnTallerThanTheScreen() {
        let screen = CGSize(width: 390, height: 700)

        let height = VoteView.photoHeight(for: CGSize(width: 1000, height: 3000), in: screen)

        #expect(height == 700)
    }

    @Test func aPhotoOfUnknownShapeTakesPartOfTheScreen() {
        let screen = CGSize(width: 390, height: 700)

        let height = VoteView.photoHeight(for: .zero, in: screen)

        #expect(height > 0)
        #expect(height < screen.height)
    }

    @Test func aWidePhotoOnAPhoneOnItsSideFitsTheHeight() {
        let height = VoteView.photoHeight(
            for: CGSize(width: 3000, height: 2000),
            in: CGSize(width: 844, height: 300)
        )

        #expect(height == 300)
    }

    @Test func eachStarIsReadWithItsCount() {
        #expect(VoteView.spokenLabel(for: 1, in: 1...5) == "1 star, poor")
        #expect(VoteView.spokenLabel(for: 3, in: 1...5) == "3 stars")
        #expect(VoteView.spokenLabel(for: 5, in: 1...5) == "5 stars, excellent")
    }
}
