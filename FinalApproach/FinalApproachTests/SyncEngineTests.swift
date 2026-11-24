import FinalApproachCore
import Foundation
import Testing
import UIKit

@testable import FinalApproach

/// A backend that can be made to fail, wrapped around the in-memory one.
@MainActor
private final class UnreliableBackend: PhotoBackend {
    let inner = SamplePhotoBackend()
    var failsDeletes = false
    var failsSaves = false
    var isSignedOut = false
    /// Ids the listing reports as records this version cannot read.
    var unreadableIDs: Set<String> = []
    /// Runs once, just before the next save reaches the backend.
    var beforeNextSave: (() async throws -> Void)?
    private(set) var saveCount = 0
    private(set) var imageFetchCount = 0

    func listPhotos() async throws -> RemoteListing {
        if isSignedOut { throw PhotoBackendError.notSignedIn }
        var listing = try await inner.listPhotos()
        listing.photos.removeAll { unreadableIDs.contains($0.photo.id) }
        listing.unreadableIDs = unreadableIDs
        return listing
    }

    func savePhoto(_ photo: SpottedPhoto, image: Data?) async throws -> SavedPhoto {
        if let hook = beforeNextSave {
            beforeNextSave = nil
            try await hook()
        }
        if failsSaves { throw PhotoBackendError.unavailable(status: 503) }
        saveCount += 1
        return try await inner.savePhoto(photo, image: image)
    }

    func fetchImage(from url: URL) async throws -> Data? {
        imageFetchCount += 1
        return try await inner.fetchImage(from: url)
    }

    func deletePhoto(id: String) async throws {
        if failsDeletes { throw PhotoBackendError.unavailable(status: 503) }
        try await inner.deletePhoto(id: id)
    }

    func deleteAccount() async throws {
        try await inner.deleteAccount()
    }
}

/// Sync between a device and the backend, and between two devices that
/// share one account. Each device gets its own empty folder.
@MainActor
final class SyncEngineTests {
    private let root: URL
    private let backend = UnreliableBackend()

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "final-approach-sync-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func store(_ device: String) -> FilePhotoStore {
        FilePhotoStore(directory: root.appending(path: device, directoryHint: .isDirectory))
    }

    private func device(_ name: String) -> CollectionModel {
        SampleData.model(store: store(name))
    }

    private func engine() -> SyncEngine {
        SyncEngine(backend: backend)
    }

    private func loggedPhoto(_ id: String = "imported-1", type: String = "Boeing 737-800", day: Double = 0) -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: type,
            registration: "N8642E",
            airline: "Southwest Airlines",
            activity: "",
            loggedAt: Date(timeIntervalSince1970: 1_800_000_000 + day * 86_400),
            captureCoordinate: Coordinate(latitude: 33.6220, longitude: -84.3995),
            spotID: "atl-south-approach",
            isLocationUndisclosed: true,
            status: .logged
        )
    }

    private func tinyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func rename(_ model: CollectionModel, _ id: String, to type: String) {
        model.updateDetails(forPhotoID: id, aircraftType: type, registration: nil, airline: "Southwest Airlines")
    }

    // MARK: Sending

    @Test func aLoggedPhotoAndItsImageReachTheBackend() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())

        let report = try await engine().run(on: phone)

        #expect(report == SyncReport(uploaded: 1))
        #expect(backend.inner.photos["imported-1"] == loggedPhoto())
        #expect(backend.inner.images["imported-1"] == store("phone").imageData(forPhotoID: "imported-1"))
        #expect(phone.syncLedger.records["imported-1"]?.imageSent == true)
    }

    @Test func aSecondSyncWithNothingNewDoesNothing() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)

        let report = try await engine().run(on: phone)

        #expect(report == SyncReport())
        #expect(backend.saveCount == 1)
    }

    @Test func theSamplePhotosAreNeverSent() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())

        try await engine().run(on: phone)

        #expect(Set(backend.inner.photos.keys) == ["imported-1"])
    }

    @Test func whatWasSentIsRememberedWhenTheAppReopens() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)

        let reopened = device("phone")
        let report = try await engine().run(on: reopened)

        #expect(reopened.syncLedger == phone.syncLedger)
        #expect(report == SyncReport())
        #expect(backend.saveCount == 1)
    }

    @Test func anEditIsSentWithoutSendingTheImageAgain() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)
        let image = backend.inner.images["imported-1"]

        rename(phone, "imported-1", to: "Boeing 737-700")
        let report = try await engine().run(on: phone)

        #expect(report == SyncReport(uploaded: 1))
        #expect(backend.inner.photos["imported-1"]?.aircraftType == "Boeing 737-700")
        #expect(backend.inner.images["imported-1"] == image)
    }

    @Test func aFailedUploadIsCountedAndTriedAgain() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        backend.failsSaves = true

        let failed = try await engine().run(on: phone)
        #expect(failed == SyncReport(failed: 1))
        #expect(!failed.isClean)

        backend.failsSaves = false
        let retried = try await engine().run(on: phone)
        #expect(retried == SyncReport(uploaded: 1))
    }

    // MARK: Two devices

    @Test func aPhotoLoggedOnOneDeviceArrivesOnTheOtherWithItsImage() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)

        let tablet = device("tablet")
        let report = try await engine().run(on: tablet)

        #expect(report == SyncReport(downloaded: 1))
        #expect(tablet.photo(id: "imported-1") == loggedPhoto())
        #expect(tablet.hasStoredImage(forPhotoID: "imported-1"))
        #expect(store("tablet").imageData(forPhotoID: "imported-1") == store("phone").imageData(forPhotoID: "imported-1"))
        // It is still there when the tablet reopens, and nothing is owed.
        let reopened = device("tablet")
        #expect(reopened.photo(id: "imported-1") == loggedPhoto())
        #expect(try await engine().run(on: reopened) == SyncReport())
    }

    @Test func fetchedPhotosSitNewestFirstAheadOfTheSamples() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto("imported-old", day: 0), image: tinyImage())
        phone.add(loggedPhoto("imported-new", day: 2), image: tinyImage())
        try await engine().run(on: phone)

        let tablet = device("tablet")
        tablet.add(loggedPhoto("imported-middle", day: 1), image: tinyImage())
        try await engine().run(on: tablet)

        let own = tablet.photos.filter { !$0.isSample }.map(\.id)
        #expect(own == ["imported-new", "imported-middle", "imported-old"])
        #expect(tablet.photos.prefix(3).allSatisfy { !$0.isSample })
    }

    @Test func anEditOnOneDeviceArrivesOnTheOtherWithoutFetchingTheImageAgain() async throws {
        let phone = device("phone")
        let tablet = device("tablet")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)
        try await engine().run(on: tablet)
        let fetches = backend.imageFetchCount

        rename(phone, "imported-1", to: "Boeing 737-700")
        try await engine().run(on: phone)
        let report = try await engine().run(on: tablet)

        #expect(report == SyncReport(downloaded: 1))
        #expect(tablet.photo(id: "imported-1")?.aircraftType == "Boeing 737-700")
        #expect(backend.imageFetchCount == fetches)
    }

    @Test func whenBothDevicesEditTheDeviceSyncingKeepsItsOwnEdit() async throws {
        let phone = device("phone")
        let tablet = device("tablet")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)
        try await engine().run(on: tablet)

        rename(phone, "imported-1", to: "Phone edit")
        try await engine().run(on: phone)
        rename(tablet, "imported-1", to: "Tablet edit")
        try await engine().run(on: tablet)

        #expect(tablet.photo(id: "imported-1")?.aircraftType == "Tablet edit")
        #expect(backend.inner.photos["imported-1"]?.aircraftType == "Tablet edit")
    }

    // MARK: Deleting

    @Test func deletingAPhotoRemovesItAndItsImageFromTheBackend() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)

        phone.deletePhoto(id: "imported-1")
        #expect(phone.syncLedger.pendingDeletes == ["imported-1"])
        let report = try await engine().run(on: phone)

        #expect(report == SyncReport(deletedThere: 1))
        #expect(backend.inner.photos.isEmpty)
        #expect(backend.inner.images.isEmpty)
        #expect(phone.syncLedger == SyncLedger())
    }

    @Test func aDeleteThatCannotReachTheBackendIsStillOwedAfterTheAppReopens() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)
        phone.deletePhoto(id: "imported-1")

        backend.failsDeletes = true
        let failed = try await engine().run(on: phone)
        #expect(failed == SyncReport(failed: 1))
        #expect(backend.inner.images["imported-1"] != nil)

        // The app closes and opens again. The delete is still owed.
        let reopened = device("phone")
        #expect(reopened.syncLedger.pendingDeletes == ["imported-1"])
        #expect(reopened.photo(id: "imported-1") == nil)

        backend.failsDeletes = false
        let retried = try await engine().run(on: reopened)
        #expect(retried == SyncReport(deletedThere: 1))
        #expect(backend.inner.photos.isEmpty)
        #expect(backend.inner.images.isEmpty)
    }

    @Test func aPhotoDeletedOnOneDeviceIsRemovedFromTheOtherWithItsImage() async throws {
        let phone = device("phone")
        let tablet = device("tablet")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)
        try await engine().run(on: tablet)

        phone.deletePhoto(id: "imported-1")
        try await engine().run(on: phone)
        let report = try await engine().run(on: tablet)

        #expect(report == SyncReport(deletedHere: 1))
        #expect(tablet.photo(id: "imported-1") == nil)
        #expect(store("tablet").imageData(forPhotoID: "imported-1") == nil)
        #expect(tablet.syncLedger == SyncLedger())
    }

    @Test func aDeleteElsewhereWinsOverAnEditHere() async throws {
        let phone = device("phone")
        let tablet = device("tablet")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)
        try await engine().run(on: tablet)

        phone.deletePhoto(id: "imported-1")
        try await engine().run(on: phone)
        rename(tablet, "imported-1", to: "Edited after the delete")
        try await engine().run(on: tablet)

        #expect(tablet.photo(id: "imported-1") == nil)
        #expect(backend.inner.photos.isEmpty)
    }

    @Test func aPhotoThatWasNeverSentLeavesNothingOwingWhenDeleted() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        phone.deletePhoto(id: "imported-1")

        #expect(phone.syncLedger == SyncLedger())
        #expect(try await engine().run(on: phone) == SyncReport())
    }

    @Test func aPhotoDeletedWhileItIsBeingSentIsStillRemovedFromTheBackend() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        backend.beforeNextSave = { phone.deletePhoto(id: "imported-1") }

        try await engine().run(on: phone)
        // The save went through after the delete, so the backend holds it.
        #expect(backend.inner.photos["imported-1"] != nil)
        #expect(phone.syncLedger.pendingDeletes == ["imported-1"])

        let report = try await engine().run(on: phone)
        #expect(report == SyncReport(deletedThere: 1))
        #expect(backend.inner.photos.isEmpty)
        #expect(backend.inner.images.isEmpty)
    }

    @Test func aPhotoDeletedElsewhereJustBeforeItIsSentIsRemovedHere() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)
        rename(phone, "imported-1", to: "Boeing 737-700")
        let inner = backend.inner
        backend.beforeNextSave = { try await inner.deletePhoto(id: "imported-1") }

        let report = try await engine().run(on: phone)

        #expect(report == SyncReport(deletedHere: 1))
        #expect(phone.photo(id: "imported-1") == nil)
        #expect(store("phone").imageData(forPhotoID: "imported-1") == nil)
    }

    @Test func deletingTheAccountOnTheDeviceLeavesNothingForASyncToRemember() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await engine().run(on: phone)

        phone.deleteAccountAndPhotos()

        #expect(phone.syncLedger == SyncLedger())
        #expect(device("phone").syncLedger == SyncLedger())
    }

    // MARK: Things a sync leaves alone or stops for

    @Test func aRecordThisVersionCannotReadIsLeftAloneOnBothSides() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        backend.unreadableIDs = ["imported-1"]

        let report = try await engine().run(on: phone)

        #expect(report == SyncReport())
        #expect(backend.saveCount == 0)
        #expect(phone.photo(id: "imported-1") == loggedPhoto())
    }

    @Test func aSyncStopsWhenNoOneIsSignedIn() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        backend.isSignedOut = true

        await #expect(throws: PhotoBackendError.notSignedIn) {
            try await self.engine().run(on: phone)
        }
        #expect(phone.syncLedger == SyncLedger())
    }

    @Test func aSyncStopsWhenTheAccountWasDeleted() async throws {
        let phone = device("phone")
        phone.add(loggedPhoto(), image: tinyImage())
        try await backend.deleteAccount()

        await #expect(throws: PhotoBackendError.accountDeleted) {
            try await self.engine().run(on: phone)
        }
        // The photo stays on the device. Removing it is the user's choice.
        #expect(phone.photo(id: "imported-1") != nil)
    }

    @Test func aLibrarySavedBeforeSyncExistedStillOpens() throws {
        let folder = root.appending(path: "old", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = #"{"photos":[],"removedSampleIDs":["sample-1"]}"#
        try Data(old.utf8).write(to: folder.appending(path: "library.json", directoryHint: .notDirectory))

        let library = try FilePhotoStore(directory: folder).loadLibrary()

        #expect(library.removedSampleIDs == ["sample-1"])
        #expect(library.syncLedger == nil)
    }
}
