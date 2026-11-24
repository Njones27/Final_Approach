import FinalApproachCore
import Foundation

/// Where each of the user's posted photos stands with the vote.
struct PostListing: Equatable {
    /// The standing of each posted photo, by photo id.
    var standings: [String: PostStanding] = [:]
    /// The fewest votes a photo needs before its grade can be final. The
    /// backend decides it, so it can change with no release.
    var minimumVotes: Int?
}

/// The backend's routes for putting a photo in front of other users.
///
/// It sits behind a protocol so posting can be built, previewed, and tested
/// with no network. A post shows other users the image and nothing else.
/// No call here sends where a photo was taken.
protocol PostBackend {
    /// Opens one saved photo for votes and gives back where it stands. The
    /// record and the image must have reached the backend first. Posting a
    /// photo twice changes nothing and gives back the first post.
    func post(photoID: String) async throws -> PostStanding
    /// Every post the user has made.
    func listPosts() async throws -> PostListing
}
