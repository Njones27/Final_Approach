import Foundation

/// One photo waiting for the user's vote.
///
/// Voting is blind. The backend gives a random id and a link to the image,
/// and nothing else. There is no photographer, no place, no count, and no
/// score here, so none of them can sway the vote or be shown by mistake.
struct VotePost: Equatable, Identifiable {
    /// The post's random id. It does not name the owner or the photo.
    let id: String
    /// A link to the image that works for a few minutes.
    let imageURL: URL
}

/// Some photos to vote on, as the backend hands them out.
struct VoteQueue: Equatable {
    var posts: [VotePost] = []
    /// The most stars a vote can give. The backend decides it, so it can
    /// change with no release.
    var scaleMax: Int?
}

/// The backend's routes for voting on other users' photos.
///
/// It sits behind a protocol so the voting screen can be built, previewed,
/// and tested with no network.
protocol VoteBackend {
    /// Some open photos the user has not voted on. It never holds the
    /// user's own photos.
    func queue() async throws -> VoteQueue
    /// The image behind a link from `queue`, or nil when the link ran out
    /// or the image is gone.
    func image(from url: URL) async throws -> Data?
    /// Counts the user's vote on one post, as a whole number of stars. A
    /// vote is cast once and cannot be changed.
    func cast(_ value: Int, onPostID postID: String) async throws
}
