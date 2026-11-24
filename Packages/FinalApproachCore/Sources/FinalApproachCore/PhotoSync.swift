/// One of the user's photos as the device holds it, for syncing.
public struct LocalPhotoState: Sendable, Equatable {
    public let id: String
    /// A value that changes whenever the saved record changes. The app
    /// makes it, and this package only compares it.
    public let fingerprint: String
    /// Whether the device holds the photo's image.
    public let hasImage: Bool

    public init(id: String, fingerprint: String, hasImage: Bool) {
        self.id = id
        self.fingerprint = fingerprint
        self.hasImage = hasImage
    }
}

/// One of the user's photos as the backend holds it.
public struct RemotePhotoState: Sendable, Equatable {
    public let id: String
    /// The backend's own mark for the record, which changes on every save.
    public let version: String

    public init(id: String, version: String) {
        self.id = id
        self.version = version
    }
}

/// What the device remembers about one photo from the last time the device
/// and the backend held the same record.
public struct SyncRecord: Sendable, Equatable, Codable {
    /// The device's fingerprint of the record at that time.
    public var localFingerprint: String
    /// The backend's version of the record at that time.
    public var remoteVersion: String
    /// Whether the backend took the image.
    public var imageSent: Bool

    public init(localFingerprint: String, remoteVersion: String, imageSent: Bool) {
        self.localFingerprint = localFingerprint
        self.remoteVersion = remoteVersion
        self.imageSent = imageSent
    }
}

/// What the device remembers between syncs.
public struct SyncLedger: Sendable, Equatable, Codable {
    /// One entry for each photo the device and the backend have agreed on.
    public var records: [String: SyncRecord]
    /// Photos deleted on this device that the backend has not confirmed yet.
    /// A delete stays here until it is confirmed, so a failed request cannot
    /// leave a deleted photo's image on the backend.
    public var pendingDeletes: Set<String>

    public init(records: [String: SyncRecord] = [:], pendingDeletes: Set<String> = []) {
        self.records = records
        self.pendingDeletes = pendingDeletes
    }

    /// Call before a photo is first sent. It leaves a mark that the backend
    /// may hold the photo, so deleting it later still tells the backend, even
    /// when the answer to the upload was lost. A photo already in the ledger
    /// is left as it is.
    public mutating func noteUploadStarted(id: String) {
        guard records[id] == nil else { return }
        records[id] = SyncRecord(localFingerprint: "", remoteVersion: "", imageSent: false)
    }

    /// Call when the backend took the record. `imageSent` says whether this
    /// upload also delivered the image. An image delivered earlier stays
    /// counted.
    public mutating func noteUploaded(id: String, fingerprint: String, version: String, imageSent: Bool) {
        let sentBefore = records[id]?.imageSent ?? false
        records[id] = SyncRecord(
            localFingerprint: fingerprint,
            remoteVersion: version,
            imageSent: sentBefore || imageSent
        )
    }

    /// Call when the device took the backend's record. `fingerprint` is the
    /// device's fingerprint of the record it saved. `imageFetched` says
    /// whether the image came from the backend too, which shows the backend
    /// holds it.
    public mutating func noteDownloaded(id: String, fingerprint: String, version: String, imageFetched: Bool) {
        let sentBefore = records[id]?.imageSent ?? false
        records[id] = SyncRecord(
            localFingerprint: fingerprint,
            remoteVersion: version,
            imageSent: sentBefore || imageFetched
        )
    }

    /// Call when the image of a record the device already holds was fetched.
    public mutating func noteImageFetched(id: String) {
        records[id]?.imageSent = true
    }

    /// Call when the user deletes a photo on this device. A photo the backend
    /// may hold is kept as a pending delete until the backend confirms it. A
    /// photo that was never sent leaves no trace.
    public mutating func noteDeletedHere(id: String) {
        if records.removeValue(forKey: id) != nil {
            pendingDeletes.insert(id)
        }
    }

    /// Call when the backend confirmed a delete, or listed the photo as
    /// deleted.
    public mutating func noteDeleteSettled(id: String) {
        records.removeValue(forKey: id)
        pendingDeletes.remove(id)
    }
}

/// One step of a sync.
public enum SyncAction: Sendable, Equatable {
    /// Tell the backend to delete a photo and its image.
    case deleteRemote(id: String)
    /// Remove a photo and its image from the device, because it was deleted
    /// somewhere else.
    case deleteLocal(id: String)
    /// Send the record, and the image too when `withImage` is set.
    case upload(id: String, withImage: Bool)
    /// Fetch the record. The image is fetched too when `withImage` is set.
    case download(id: String, withImage: Bool)
    /// Fetch only the image of a record the device already holds.
    case fetchImage(id: String)
}

/// Decides what a sync has to do.
public enum SyncPlan {
    /// The steps that bring the device and the backend into line.
    ///
    /// Deletes come first and always win. A photo deleted anywhere is gone
    /// everywhere, and is never sent or fetched again. When a record changed
    /// on this device and on the backend since they last agreed, the device's
    /// copy is sent, because it holds the edit the user just made.
    ///
    /// - Parameters:
    ///   - local: The user's own photos on the device. Sample photos are left out.
    ///   - remote: The photos the backend listed.
    ///   - remoteDeleted: The ids the backend listed as deleted.
    ///   - ledger: What the device remembers from earlier syncs.
    /// - Returns: The steps in the order to run them. Each group is sorted
    ///   by id, so the same inputs always give the same plan.
    public static func actions(
        local: [LocalPhotoState],
        remote: [RemotePhotoState],
        remoteDeleted: Set<String>,
        ledger: SyncLedger
    ) -> [SyncAction] {
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let gone = ledger.pendingDeletes.union(remoteDeleted)

        var actions: [SyncAction] = []

        // The backend already holds its own mark for a photo it listed as
        // deleted, so only the others still need telling.
        for id in ledger.pendingDeletes.subtracting(remoteDeleted).sorted() {
            actions.append(.deleteRemote(id: id))
        }
        for id in remoteDeleted.sorted() where localByID[id] != nil {
            actions.append(.deleteLocal(id: id))
        }

        for id in localByID.keys.sorted() where !gone.contains(id) {
            guard let photo = localByID[id] else { continue }
            let record = ledger.records[id]
            guard let listed = remoteByID[id] else {
                // The backend has never taken this photo, or lost it.
                actions.append(.upload(id: id, withImage: photo.hasImage))
                continue
            }
            let changedHere = record?.localFingerprint != photo.fingerprint
            let changedThere = record?.remoteVersion != listed.version
            let imageOwed = photo.hasImage && record?.imageSent != true
            if changedHere {
                actions.append(.upload(id: id, withImage: imageOwed))
            } else if changedThere {
                actions.append(.download(id: id, withImage: !photo.hasImage))
            } else if imageOwed {
                actions.append(.upload(id: id, withImage: true))
            } else if !photo.hasImage {
                actions.append(.fetchImage(id: id))
            }
        }

        for id in remoteByID.keys.sorted() where localByID[id] == nil && !gone.contains(id) {
            actions.append(.download(id: id, withImage: true))
        }

        return actions
    }
}
