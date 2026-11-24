import Foundation

/// One of the user's photos as the backend holds it.
struct RemotePhoto: Equatable {
    let photo: SpottedPhoto
    /// The backend's own mark for the record, which changes on every save.
    let version: String
    /// A link to the image that works for a few minutes.
    let imageURL: URL
}

/// Everything the backend holds for the signed in user.
struct RemoteListing: Equatable {
    var photos: [RemotePhoto] = []
    /// Photos that were deleted, here or on another device.
    var deletedIDs: Set<String> = []
    /// Photos whose record this version of the app cannot read, most likely
    /// because a newer version saved them. A sync leaves them alone.
    var unreadableIDs: Set<String> = []
}

/// What the backend answered when it took a photo.
struct SavedPhoto: Equatable {
    /// The backend's mark for the record it saved.
    let version: String
    /// Whether the image reached the backend as well. It is false when no
    /// image was sent, and when the record was saved but the image was not.
    let imageSent: Bool
}

/// Why the backend turned a request away.
enum PhotoBackendError: Error, Equatable {
    /// No one is signed in, or the sign in ran out.
    case notSignedIn
    /// The photo was deleted, so it cannot be saved again.
    case photoDeleted
    /// The account was deleted, so it takes nothing more.
    case accountDeleted
    /// A sample photo ships with the app and is never sent.
    case notTheUsersPhoto
    /// The photo's record or image has not reached the backend yet, so it
    /// cannot be posted. A sync sends them.
    case photoNotSaved
    /// The image has a location written inside it, so the backend will not
    /// show it to other users.
    case imageHasLocation
    /// The user has already voted on this post. A vote cannot be changed.
    case alreadyVoted
    /// Voting on this post has closed, or the post is gone.
    case votingClosed
    /// The post is the user's own photo, which they cannot vote on.
    case ownPost
    /// The backend refused the request. The message is the backend's own.
    case refused(status: Int, message: String)
    /// The backend failed, and the request may work later.
    case unavailable(status: Int)
    /// The answer was not in the shape the app expects.
    case unreadableAnswer
}

/// The backend's copy of the signed in user's own photos.
///
/// It sits behind a protocol so sync can be built, previewed, and tested
/// with no network. Every call is about the signed in user only. Nothing
/// here reads another user's photo, so a private location never leaves its
/// owner.
protocol PhotoBackend {
    /// Every photo and every deleted photo id the backend holds for the user.
    func listPhotos() async throws -> RemoteListing
    /// Saves the photo's record, and its image too when one is given.
    func savePhoto(_ photo: SpottedPhoto, image: Data?) async throws -> SavedPhoto
    /// The image behind a link from `listPhotos`, or nil when the backend
    /// has no image for that photo yet or the link ran out.
    func fetchImage(from url: URL) async throws -> Data?
    /// Deletes the photo and its image. Deleting a photo twice is fine.
    func deletePhoto(id: String) async throws
    /// Deletes every image and record the user has, and their sign in.
    func deleteAccount() async throws
}
