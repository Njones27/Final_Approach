import FinalApproachCore
import Foundation

/// Posting kept in memory, for previews and tests. It follows the real
/// backend's rules. A photo is posted once, only after its record and
/// image were saved, and a deleted photo has no post.
final class SamplePostBackend: PostBackend {
    /// The backend that holds the photos, which says what was saved.
    private let photos: SamplePhotoBackend
    private let windowSeconds: Double
    private let minimumVotes: Int
    private let now: () -> Date
    private var standings: [String: PostStanding] = [:]
    /// The spot's page each posted photo is shown on, by photo id.
    private(set) var showings: [String: SpotShowing] = [:]
    /// The spots a photo may be shown at. With nil every spot is listed.
    var listedSpotIDs: Set<String>?
    /// How many of the next posts are refused because the image carries a
    /// location.
    var imageRefusalsLeft = 0
    /// How many posts were asked for.
    private(set) var postAttempts = 0
    /// Makes the next request to show a photo at a spot fail with this,
    /// once.
    var nextShowFailure: PhotoBackendError?
    /// How many times a photo was put on a spot's page.
    private(set) var showCount = 0

    init(
        photos: SamplePhotoBackend,
        rules: VotingRules = .launch,
        now: @escaping () -> Date = { Date() }
    ) {
        self.photos = photos
        windowSeconds = rules.windowSeconds
        minimumVotes = rules.minimumVotes
        self.now = now
    }

    func post(photoID: String) async throws -> PostStanding {
        if photos.isAccountDeleted { throw PhotoBackendError.accountDeleted }
        if photos.deletedIDs.contains(photoID) { throw PhotoBackendError.photoDeleted }
        guard photos.photos[photoID] != nil, photos.images[photoID] != nil else {
            throw PhotoBackendError.photoNotSaved
        }
        postAttempts += 1
        if imageRefusalsLeft > 0 {
            imageRefusalsLeft -= 1
            throw PhotoBackendError.imageHasLocation
        }
        if let existing = standings[photoID] { return existing }
        let posted = now()
        let standing = PostStanding(
            postedAt: posted,
            closesAt: posted.addingTimeInterval(windowSeconds),
            voteCount: 0
        )
        standings[photoID] = standing
        return standing
    }

    func listPosts() async throws -> PostListing {
        if photos.isAccountDeleted { throw PhotoBackendError.accountDeleted }
        // Deleting a photo takes its post down.
        let live = standings.filter { photos.photos[$0.key] != nil }
        return PostListing(
            standings: live,
            showings: showings.filter { live[$0.key] != nil },
            minimumVotes: minimumVotes
        )
    }

    func show(photoID: String, at showing: SpotShowing) async throws -> SpotShowing {
        if photos.isAccountDeleted { throw PhotoBackendError.accountDeleted }
        if let failure = nextShowFailure {
            nextShowFailure = nil
            throw failure
        }
        if let listedSpotIDs, !listedSpotIDs.contains(showing.spotID) {
            throw PhotoBackendError.unknownSpot
        }
        guard standings[photoID] != nil, photos.photos[photoID] != nil else {
            throw PhotoBackendError.notPosted
        }
        showCount += 1
        showings[photoID] = showing
        return showing
    }

    func hide(photoID: String) async throws {
        if photos.isAccountDeleted { throw PhotoBackendError.accountDeleted }
        showings[photoID] = nil
    }

    /// Sets where a posted photo stands, as votes from other users would.
    /// A test or a preview uses it to show voting under way or a grade.
    func setStanding(voteCount: Int, finalScore: Int? = nil, forPhotoID id: String) {
        guard let current = standings[id] else { return }
        standings[id] = PostStanding(
            postedAt: current.postedAt,
            closesAt: current.closesAt,
            voteCount: voteCount,
            finalScore: finalScore
        )
    }
}
