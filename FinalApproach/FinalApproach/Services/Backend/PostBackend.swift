import FinalApproachCore
import Foundation

/// The spot's page one of the user's posted photos is shown on, with what
/// other people read beside it there.
///
/// It holds no position. A spot is a listed place that many people use, and
/// the page shows the photo only once it is graded.
struct SpotShowing: Equatable, Codable {
    let spotID: String
    /// The aircraft type shown beside the photo, or nil to show none.
    var aircraftType: String?
    /// The airline shown beside the photo, or nil to show none.
    var airline: String?
}

/// Where each of the user's posted photos stands with the vote.
struct PostListing: Equatable {
    /// The standing of each posted photo, by photo id.
    var standings: [String: PostStanding] = [:]
    /// The spot's page each posted photo is shown on, by photo id. A photo
    /// that is on no page is left out.
    var showings: [String: SpotShowing] = [:]
    /// The fewest votes a photo needs before its grade can be final. The
    /// backend decides it, so it can change with no release.
    var minimumVotes: Int?
}

/// The backend's routes for putting a photo in front of other users.
///
/// It sits behind a protocol so posting can be built, previewed, and tested
/// with no network. A post shows voters the image and nothing else. No call
/// here sends where a photo was taken. Showing a photo at a spot names a
/// listed spot, and only its owner can ask for that.
protocol PostBackend {
    /// Opens one saved photo for votes and gives back where it stands. The
    /// record and the image must have reached the backend first. Posting a
    /// photo twice changes nothing and gives back the first post.
    func post(photoID: String) async throws -> PostStanding
    /// Every post the user has made.
    func listPosts() async throws -> PostListing
    /// Puts one posted photo on a spot's page, and gives back what the
    /// backend kept. The page shows it once it is graded. Asking again
    /// replaces the spot and the words beside the photo.
    func show(photoID: String, at showing: SpotShowing) async throws -> SpotShowing
    /// Takes one photo off every spot's page. Doing it twice is fine.
    func hide(photoID: String) async throws
}
