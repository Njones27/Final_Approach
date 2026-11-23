import Foundation

/// Everything about the user's collection that is saved on the device,
/// apart from the image files.
struct StoredLibrary: Equatable, Codable {
    /// The photos the user logged, newest first.
    var photos: [SpottedPhoto] = []
    /// The sample photos the user deleted, so they stay deleted.
    var removedSampleIDs: [String] = []
}

/// Keeps the user's logged photos and their images on the device.
///
/// It sits behind a protocol so screens can be previewed and tested with no
/// files, and so a backend copy can join it later.
protocol PhotoStore {
    /// The saved library. A device with nothing saved gives an empty one.
    func loadLibrary() throws -> StoredLibrary
    func saveLibrary(_ library: StoredLibrary) throws
    func saveImage(_ data: Data, forPhotoID id: String) throws
    /// The saved image file, or nil when there is none.
    func imageData(forPhotoID id: String) -> Data?
    func deleteImage(forPhotoID id: String) throws
    /// Removes the library and every image.
    func deleteEverything() throws
}

/// A photo store made of plain files. The library is one JSON file and each
/// image is a JPEG named by its photo id.
///
/// The images are saved from the copy made for the screen, which carries no
/// metadata, so a saved file holds no location.
struct FilePhotoStore: PhotoStore {
    let directory: URL

    /// The store the app uses, inside Application Support.
    static var standard: FilePhotoStore {
        let support = URL.applicationSupportDirectory
        return FilePhotoStore(directory: support.appending(path: "Collection", directoryHint: .isDirectory))
    }

    private var libraryURL: URL {
        directory.appending(path: "library.json", directoryHint: .notDirectory)
    }

    private var imagesDirectory: URL {
        directory.appending(path: "Images", directoryHint: .isDirectory)
    }

    func loadLibrary() throws -> StoredLibrary {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            return StoredLibrary()
        }
        let data = try Data(contentsOf: libraryURL)
        return try JSONDecoder().decode(StoredLibrary.self, from: data)
    }

    func saveLibrary(_ library: StoredLibrary) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // An atomic write leaves the old file whole if the app stops midway.
        try encoder.encode(library).write(to: libraryURL, options: .atomic)
    }

    func saveImage(_ data: Data, forPhotoID id: String) throws {
        guard let url = imageURL(forPhotoID: id) else { throw PhotoStoreError.unusablePhotoID }
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func imageData(forPhotoID id: String) -> Data? {
        guard let url = imageURL(forPhotoID: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    func deleteImage(forPhotoID id: String) throws {
        guard let url = imageURL(forPhotoID: id),
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        try FileManager.default.removeItem(at: url)
    }

    func deleteEverything() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// The file for one photo's image. A photo id is used as a file name,
    /// so an id that could point outside the images folder gets no file.
    private func imageURL(forPhotoID id: String) -> URL? {
        let allowed = id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !id.isEmpty, allowed else { return nil }
        return imagesDirectory.appending(path: "\(id).jpg", directoryHint: .notDirectory)
    }
}

enum PhotoStoreError: Error {
    /// The photo id cannot be used as a file name.
    case unusablePhotoID
}
