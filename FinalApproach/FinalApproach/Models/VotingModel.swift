import FinalApproachCore
import Foundation
import Observation
import UIKit

/// Runs the Vote screen against the backend. It asks for photos to vote on,
/// shows one at a time, and casts the user's vote.
///
/// Voting is blind. All this holds about a photo is a random id and the
/// image, so the screen has no name, place, count, or score to show.
@Observable
final class VotingModel {
    enum Phase: Equatable {
        /// Nothing has been asked for yet.
        case idle
        case loading
        /// A photo is on the screen, waiting for a vote.
        case voting
        /// There is nothing left to vote on for now.
        case empty
        case signInNeeded
        /// The backend could not be reached.
        case couldNotLoad
    }

    /// The photo on the screen.
    struct Ballot: Identifiable {
        /// The post's random id.
        let id: String
        let image: UIImage
    }

    private(set) var phase: Phase = .idle
    private(set) var ballot: Ballot?
    /// True while a vote is on its way to the backend.
    private(set) var isCasting = false
    /// How many votes the backend counted on this visit.
    private(set) var votesCast = 0
    /// True when the last vote did not reach the backend. The photo stays
    /// on the screen so the user can try again.
    private(set) var lastVoteFailed = false
    /// The stars a vote can give. The backend can change the top of it.
    private(set) var scale: ClosedRange<Int>

    let session: AccountSession

    @ObservationIgnored private let backend: (any VoteBackend)?
    /// The most stars the screen has room for. A larger scale from the
    /// backend is ignored.
    @ObservationIgnored private let largestScale: Int
    /// Posts handed out by the backend and not shown yet.
    @ObservationIgnored private var pending: [VotePost] = []
    /// Posts the user voted on or skipped on this visit. The backend may
    /// hand a skipped one out again, and it is not shown twice.
    @ObservationIgnored private var setAside: Set<String> = []
    /// The user the photos were asked for. A different user starts over.
    @ObservationIgnored private var loadedFor: String?
    @ObservationIgnored private var isWorking = false

    /// Pass no backend for a build that has none. Such a build keeps the
    /// sample set on the Vote screen.
    init(
        session: AccountSession,
        backend: (any VoteBackend)?,
        rules: VotingRules = .launch,
        largestScale: Int = 10
    ) {
        self.session = session
        self.backend = backend
        self.scale = rules.scale
        self.largestScale = largestScale
    }

    /// True when votes go to the backend. It takes a backend and a way to
    /// sign in.
    var isLive: Bool { backend != nil && session.canSignIn }

    /// True while a vote is being cast or the next photo is on its way.
    /// The screen takes no vote in the meantime.
    var isBusy: Bool { isCasting || phase == .loading }

    private var signedInUserID: String? {
        if case let .signedIn(userID) = session.state { userID } else { nil }
    }

    /// Call when the Vote screen appears and when the sign in changes. It
    /// asks for photos unless one is already on the screen.
    func refresh() async {
        guard isLive, !isWorking else { return }
        guard let userID = signedInUserID else {
            startOver(for: nil)
            phase = .signInNeeded
            return
        }
        if loadedFor != userID {
            startOver(for: userID)
        }
        guard ballot == nil || phase != .voting else { return }
        await showNext(for: userID)
    }

    /// Casts the user's vote on the photo on the screen and moves on. A
    /// vote cannot be changed, so the screen asks for it once.
    func cast(_ stars: Int) async {
        guard let backend, let ballot, let userID = signedInUserID, !isWorking, scale.contains(stars) else {
            return
        }
        isWorking = true
        isCasting = true
        lastVoteFailed = false
        var outcome = CastOutcome.failed
        do {
            try await backend.cast(stars, onPostID: ballot.id)
            outcome = .counted
        } catch PhotoBackendError.alreadyVoted, PhotoBackendError.votingClosed, PhotoBackendError.ownPost {
            // The vote cannot count, and trying again would not help.
            outcome = .cannotCount
        } catch PhotoBackendError.notSignedIn, PhotoBackendError.accountDeleted {
            outcome = .signInEnded
        } catch {
            #if DEBUG
            print("VotingModel: The vote did not reach the backend. \(error)")
            #endif
        }
        isCasting = false
        isWorking = false

        guard signedInUserID == userID, self.ballot?.id == ballot.id else {
            await refresh()
            return
        }
        switch outcome {
        case .counted:
            votesCast += 1
            await moveOn(from: ballot, for: userID)
        case .cannotCount:
            await moveOn(from: ballot, for: userID)
        case .signInEnded:
            startOver(for: nil)
            phase = .signInNeeded
        case .failed:
            lastVoteFailed = true
        }
    }

    /// Passes over the photo on the screen with no vote. It does not come
    /// back on this visit.
    func skip() async {
        guard let ballot, let userID = signedInUserID, !isWorking else { return }
        lastVoteFailed = false
        await moveOn(from: ballot, for: userID)
    }

    private enum CastOutcome {
        case counted
        case cannotCount
        case signInEnded
        case failed
    }

    /// The photo stays on the screen until the next one is ready, so the
    /// screen does not go blank between two photos.
    private func moveOn(from ballot: Ballot, for userID: String) async {
        setAside.insert(ballot.id)
        await showNext(for: userID)
    }

    private func startOver(for userID: String?) {
        loadedFor = userID
        ballot = nil
        pending = []
        setAside = []
        votesCast = 0
        lastVoteFailed = false
        phase = .idle
    }

    /// Puts the next photo on the screen.
    ///
    /// The posts in hand are tried first. A link to an image works for a
    /// few minutes, so a post whose link ran out is dropped and the backend
    /// is asked again, which gives new links. The backend is asked at most
    /// twice in one go, so a run of bad posts cannot keep this going.
    private func showNext(for userID: String) async {
        guard let backend, !isWorking else { return }
        isWorking = true
        phase = .loading
        var asked = 0
        var result = Phase.empty
        var next: Ballot?

        do {
            search: while true {
                while !pending.isEmpty {
                    let post = pending.removeFirst()
                    guard !setAside.contains(post.id) else { continue }
                    let data = try await backend.image(from: post.imageURL)
                    guard signedInUserID == userID else { break search }
                    guard let data, let image = UIImage(data: data) else {
                        // A post with a new link that still has no image is
                        // gone, so it is not asked for again.
                        if asked > 0 { setAside.insert(post.id) }
                        continue
                    }
                    // The image is decoded here, off the main thread, so
                    // the screen does not stall when it first draws it.
                    let prepared = await image.byPreparingForDisplay()
                    next = Ballot(id: post.id, image: prepared ?? image)
                    result = .voting
                    break search
                }
                guard asked < 2 else { break }
                asked += 1
                let queue = try await backend.queue()
                guard signedInUserID == userID else { break search }
                if let top = queue.scaleMax, (2...largestScale).contains(top) {
                    scale = 1...top
                }
                pending = queue.posts.filter { !setAside.contains($0.id) }
                guard !pending.isEmpty else { break }
            }
        } catch PhotoBackendError.notSignedIn, PhotoBackendError.accountDeleted {
            result = .signInNeeded
        } catch {
            #if DEBUG
            print("VotingModel: The photos to vote on could not be loaded. \(error)")
            #endif
            result = .couldNotLoad
        }
        isWorking = false

        // The user signed out or changed while this ran, so it starts over.
        guard signedInUserID == userID, loadedFor == userID else {
            await refresh()
            return
        }
        if result == .signInNeeded {
            startOver(for: nil)
        }
        ballot = next
        phase = result
    }
}

extension VotingModel {
    /// The voting model the app uses, made from this build's settings. A
    /// build with no backend gets one that keeps the sample set.
    static func forThisBuild(session: AccountSession) -> VotingModel {
        var backend: (any VoteBackend)?
        if let apiURL = AppEnvironment.apiBaseURL {
            backend = HTTPVoteBackend(
                baseURL: apiURL,
                transport: URLSessionTransport.standard,
                accessToken: { try await session.accessToken() }
            )
        }
        return VotingModel(session: session, backend: backend)
    }

    /// A voting model on sample services, for previews. Nothing it does
    /// leaves the device.
    ///
    /// Pass no posts to vote on the sample set.
    static func preview(session: AccountSession, posts: [SampleVoteBackend.Post]? = nil) -> VotingModel {
        VotingModel(session: session, backend: SampleVoteBackend(posts: posts ?? SampleData.votePosts()))
    }
}
