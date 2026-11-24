import Foundation

/// A backend that keeps everything in memory. It is for previews and tests,
/// and follows the real one's rules. A deleted photo stays deleted, and a
/// deleted account takes nothing more.
final class SamplePhotoBackend: PhotoBackend {
    private(set) var photos: [String: SpottedPhoto] = [:]
    private(set) var versions: [String: String] = [:]
    private(set) var images: [String: Data] = [:]
    private(set) var deletedIDs: Set<String> = []
    private(set) var isAccountDeleted = false
    private var saves = 0

    func listPhotos() async throws -> RemoteListing {
        try checkAccount()
        let listed = photos.keys.sorted().compactMap { id -> RemotePhoto? in
            guard let photo = photos[id], let version = versions[id] else { return nil }
            return RemotePhoto(photo: photo, version: version, imageURL: Self.imageURL(forPhotoID: id))
        }
        return RemoteListing(photos: listed, deletedIDs: deletedIDs)
    }

    func savePhoto(_ photo: SpottedPhoto, image: Data?) async throws -> SavedPhoto {
        try checkAccount()
        guard !photo.isSample else { throw PhotoBackendError.notTheUsersPhoto }
        guard !deletedIDs.contains(photo.id) else { throw PhotoBackendError.photoDeleted }
        saves += 1
        let version = "save-\(saves)"
        photos[photo.id] = photo
        versions[photo.id] = version
        if let image, !image.isEmpty {
            images[photo.id] = image
            return SavedPhoto(version: version, imageSent: true)
        }
        return SavedPhoto(version: version, imageSent: false)
    }

    func fetchImage(from url: URL) async throws -> Data? {
        images[url.lastPathComponent]
    }

    func deletePhoto(id: String) async throws {
        try checkAccount()
        photos[id] = nil
        versions[id] = nil
        images[id] = nil
        deletedIDs.insert(id)
    }

    func deleteAccount() async throws {
        photos = [:]
        versions = [:]
        images = [:]
        deletedIDs = []
        isAccountDeleted = true
    }

    /// A stand in for the link the real backend gives to an image.
    static func imageURL(forPhotoID id: String) -> URL {
        URL(filePath: "/sample-backend/images").appending(path: id)
    }

    private func checkAccount() throws {
        if isAccountDeleted { throw PhotoBackendError.accountDeleted }
    }
}
