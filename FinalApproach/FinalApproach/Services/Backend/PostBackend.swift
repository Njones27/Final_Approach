import FinalApproachCore
import Foundation

/// Where one of the user's posted photos is shown to other people, with
/// what they read beside it there.
///
/// A photo is shown on the page of a listed spot, or at a place on the map
/// when it was taken away from every listed spot. A place is one cell of
/// the map's grid, about a hundred meters across. This holds the cell's id
/// and never a position, so where the photo was taken cannot be read back
/// from it. Either way the photo is shown only once it is graded.
struct SpotShowing: Equatable, Codable {
    /// The listed spot whose page the photo is on, or nil for a photo that
    /// is shown at a place.
    var spotID: String?
    /// The place the photo is shown at, such as `n33640w84428`, or nil for
    /// a photo that is on a listed spot's page.
    var placeID: String?
    /// The aircraft type shown beside the photo, or nil to show none.
    var aircraftType: String?
    /// The airline shown beside the photo, or nil to show none.
    var airline: String?
    /// The camera settings shown beside the photo, or nil to show none.
    var camera: ShownCamera?

    /// A photo on a listed spot's page.
    init(spotID: String, aircraftType: String? = nil, airline: String? = nil, camera: ShownCamera? = nil) {
        self.spotID = spotID
        self.aircraftType = aircraftType
        self.airline = airline
        self.camera = camera
    }

    /// A photo shown at a place on the map.
    init(placeID: String, aircraftType: String? = nil, airline: String? = nil, camera: ShownCamera? = nil) {
        self.placeID = placeID
        self.aircraftType = aircraftType
        self.airline = airline
        self.camera = camera
    }

    /// False for an answer that names no spot and no place, which this
    /// version cannot show.
    var isSomewhere: Bool {
        spotID != nil || placeID != nil
    }
}

/// Where each of the user's posted photos stands with the vote.
struct PostListing: Equatable {
    /// The standing of each posted photo, by photo id.
    var standings: [String: PostStanding] = [:]
    /// Where each posted photo is shown, by photo id. A photo that is
    /// shown nowhere is left out.
    var showings: [String: SpotShowing] = [:]
    /// The fewest votes a photo needs before its grade can be final. The
    /// backend decides it, so it can change with no release.
    var minimumVotes: Int?
}

/// The backend's routes for putting a photo in front of other users.
///
/// It sits behind a protocol so posting can be built, previewed, and tested
/// with no network. A post shows voters the image and nothing else. No call
/// here sends where a photo was taken. Showing a photo names a listed spot
/// or a place, which is a cell of the map about a hundred meters across,
/// and only its owner can ask for that.
protocol PostBackend {
    /// Opens one saved photo for votes and gives back where it stands. The
    /// record and the image must have reached the backend first. Posting a
    /// photo twice changes nothing and gives back the first post.
    func post(photoID: String) async throws -> PostStanding
    /// Every post the user has made.
    func listPosts() async throws -> PostListing
    /// Puts one posted photo on a spot's page or at a place on the map,
    /// and gives back what the backend kept. It is shown once it is
    /// graded. Asking again replaces where it is shown and what is read
    /// beside the photo.
    func show(photoID: String, at showing: SpotShowing) async throws -> SpotShowing
    /// Takes one photo off its spot's page or its place. Doing it twice is
    /// fine.
    func hide(photoID: String) async throws
}
