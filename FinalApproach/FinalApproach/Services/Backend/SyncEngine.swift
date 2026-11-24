import FinalApproachCore
import Foundation

/// What one sync did.
struct SyncReport: Equatable {
    var uploaded = 0
    var downloaded = 0
    var imagesFetched = 0
    /// Photos removed from the device because they were deleted elsewhere.
    var deletedHere = 0
    /// Deletes made on the device that the backend confirmed.
    var deletedThere = 0
    /// Steps that failed and are tried again on the next sync.
    var failed = 0

    /// True when the sync had nothing to do or everything worked.
    var isClean: Bool { failed == 0 }
}

/// Brings the user's photos on the device and on the backend into line.
///
/// The rules for what to do are in the core package, in `SyncPlan`. This
/// type only carries the steps out. Each step is recorded as it finishes, so
/// a sync that stops partway picks up where it stopped.
final class SyncEngine {
    private let backend: any PhotoBackend
    /// True while a sync is running. A second call waits for nothing and
    /// does nothing, so two syncs never work on the same photo.
    private(set) var isRunning = false

    init(backend: any PhotoBackend) {
        self.backend = backend
    }

    /// Runs one sync.
    ///
    /// It throws when no step can work, which is when no one is signed in,
    /// the account was deleted, or the backend cannot be listed. One photo
    /// that fails is counted in the report and tried again next time.
    ///
    /// A sync stops when every photo is removed from the device while it
    /// runs, which is what deleting the account does. Nothing it was still
    /// fetching is put back.
    @discardableResult
    func run(on model: CollectionModel) async throws -> SyncReport {
        guard !isRunning else { return SyncReport() }
        isRunning = true
        defer { isRunning = false }

        let cleared = model.timesCleared
        let listing = try await backend.listPhotos()
        guard model.timesCleared == cleared else { return SyncReport() }
        // A record this version cannot read is left alone on both sides.
        let local = model.localSyncStates().filter { !listing.unreadableIDs.contains($0.id) }
        let remote = Dictionary(listing.photos.map { ($0.photo.id, $0) }, uniquingKeysWith: { first, _ in first })

        // The backend already holds its own mark for these deletes.
        let settled = model.syncLedger.pendingDeletes.intersection(listing.deletedIDs)
        if !settled.isEmpty {
            model.updateSyncLedger { ledger in
                for id in settled { ledger.noteDeleteSettled(id: id) }
            }
        }

        let actions = SyncPlan.actions(
            local: local,
            remote: listing.photos.map { RemotePhotoState(id: $0.photo.id, version: $0.version) },
            remoteDeleted: listing.deletedIDs,
            ledger: model.syncLedger
        )

        var report = SyncReport()
        for action in actions {
            guard model.timesCleared == cleared else { break }
            do {
                try await perform(action, on: model, remote: remote, report: &report)
            } catch PhotoBackendError.notSignedIn {
                throw PhotoBackendError.notSignedIn
            } catch PhotoBackendError.accountDeleted {
                throw PhotoBackendError.accountDeleted
            } catch {
                #if DEBUG
                print("SyncEngine: A step failed and will be tried again. \(action) \(error)")
                #endif
                report.failed += 1
            }
        }
        return report
    }

    private func perform(
        _ action: SyncAction,
        on model: CollectionModel,
        remote: [String: RemotePhoto],
        report: inout SyncReport
    ) async throws {
        switch action {
        case .deleteRemote(let id):
            try await backend.deletePhoto(id: id)
            model.updateSyncLedger { $0.noteDeleteSettled(id: id) }
            report.deletedThere += 1

        case .deleteLocal(let id):
            model.removeDeletedElsewhere(id: id)
            report.deletedHere += 1

        case .upload(let id, let withImage):
            try await upload(id, withImage: withImage, on: model, report: &report)

        case .download(let id, let withImage):
            guard let listed = remote[id] else { return }
            let cleared = model.timesCleared
            let before = try model.photo(id: id)?.syncFingerprint()
            var image: Data?
            if withImage {
                image = try await backend.fetchImage(from: listed.imageURL)
            }
            // The user may have deleted or edited the photo while the image
            // was on its way, or removed every photo. Their change is newer,
            // so it stands.
            guard model.timesCleared == cleared,
                  !model.syncLedger.pendingDeletes.contains(id),
                  try model.photo(id: id)?.syncFingerprint() == before
            else { return }
            model.takeRemote(listed.photo, imageData: image)
            let fingerprint = try listed.photo.syncFingerprint()
            // Only an image that arrived and could be kept shows that the
            // backend holds one.
            let imageFetched = image != nil && model.hasStoredImage(forPhotoID: id)
            model.updateSyncLedger {
                $0.noteDownloaded(
                    id: id,
                    fingerprint: fingerprint,
                    version: listed.version,
                    imageFetched: imageFetched
                )
            }
            report.downloaded += 1

        case .fetchImage(let id):
            guard let listed = remote[id],
                  let image = try await backend.fetchImage(from: listed.imageURL),
                  model.takeRemoteImage(image, forPhotoID: id)
            else { return }
            model.updateSyncLedger { $0.noteImageFetched(id: id) }
            report.imagesFetched += 1
        }
    }

    private func upload(
        _ id: String,
        withImage: Bool,
        on model: CollectionModel,
        report: inout SyncReport
    ) async throws {
        guard let photo = model.photo(id: id), !photo.isSample else { return }
        let fingerprint = try photo.syncFingerprint()
        let image = withImage ? model.storedImageData(forPhotoID: id) : nil
        // The mark goes down first. If the answer is lost, deleting the
        // photo later still tells the backend.
        model.updateSyncLedger { $0.noteUploadStarted(id: id) }

        let saved: SavedPhoto
        do {
            saved = try await backend.savePhoto(photo, image: image)
        } catch PhotoBackendError.photoDeleted {
            // It was deleted on another device after the listing was read.
            model.removeDeletedElsewhere(id: id)
            report.deletedHere += 1
            return
        }
        // A photo the user deleted while it was being sent stays a pending
        // delete, and the next sync removes the copy that was just saved.
        guard model.photo(id: id) != nil else { return }
        model.updateSyncLedger {
            $0.noteUploaded(id: id, fingerprint: fingerprint, version: saved.version, imageSent: saved.imageSent)
        }
        report.uploaded += 1
    }
}
