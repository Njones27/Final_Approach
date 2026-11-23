import FinalApproachCore
import Foundation
import Testing
import UIKit

@testable import FinalApproach

/// The collection as it is saved on the device. Each test gets its own
/// empty folder, which is removed afterwards.
@MainActor
final class LocalCollectionTests {
    let directory: URL
    let store: FilePhotoStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "final-approach-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FilePhotoStore(directory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func loggedPhoto(
        id: String = "imported-1",
        type: String = "Boeing 737-800",
        registration: String = "N8642E",
        airline: String = "Southwest Airlines"
    ) -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: type,
            registration: registration,
            airline: airline,
            activity: "",
            capturedAt: Date(timeIntervalSince1970: 1_790_000_000),
            loggedAt: Date(timeIntervalSince1970: 1_800_000_000),
            captureCoordinate: Coordinate(latitude: 33.6220, longitude: -84.3995),
            spotID: "atl-south-approach",
            isLocationUndisclosed: true,
            status: .logged
        )
    }

    /// A real image, because an empty one has nothing to save.
    private func tinyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func imageFile(forPhotoID id: String) -> URL {
        directory
            .appending(path: "Images", directoryHint: .isDirectory)
            .appending(path: "\(id).jpg", directoryHint: .notDirectory)
    }

    // MARK: Saving

    @Test func aLoggedPhotoAndItsImageAreStillThereWhenTheAppReopens() throws {
        let photo = loggedPhoto()
        let model = SampleData.model(store: store)
        model.add(photo, image: tinyImage())
        #expect(model.storageProblem == nil)

        let reopened = SampleData.model(store: store)
        #expect(reopened.photos.first == photo)
        #expect(reopened.photos.count == SampleData.photos.count + 1)
        #expect(reopened.hasStoredImage(forPhotoID: photo.id))
        #expect(FileManager.default.fileExists(atPath: imageFile(forPhotoID: photo.id).path))
    }

    @Test func aSavedPhotoKeepsItsPrivateDetails() throws {
        let model = SampleData.model(store: store)
        model.add(loggedPhoto(), image: tinyImage())

        let saved = try #require(SampleData.model(store: store).photos.first)
        #expect(saved.visibleRegistration == "N8642E")
        #expect(saved.hasCaptureLocation)
        #expect(saved.isLocationUndisclosed)
        // An undisclosed photo still shares nothing after it is read back.
        #expect(saved.publicCaptureCoordinate == nil)
        #expect(saved.publicSpotID == nil)
    }

    @Test func theSamplePhotosAreNeverWrittenToTheDevice() throws {
        let model = SampleData.model(store: store)
        model.add(loggedPhoto(), image: tinyImage())
        #expect(try store.loadLibrary().photos.map(\.id) == ["imported-1"])
    }

    @Test func aDeviceWithNothingSavedOpensOnTheSamples() throws {
        #expect(try store.loadLibrary() == StoredLibrary())
        #expect(SampleData.model(store: store).photos.count == SampleData.photos.count)
    }

    // MARK: Deleting

    @Test func deletingALoggedPhotoRemovesItsImageFromTheDevice() throws {
        let photo = loggedPhoto()
        let model = SampleData.model(store: store)
        model.add(photo, image: tinyImage())
        #expect(FileManager.default.fileExists(atPath: imageFile(forPhotoID: photo.id).path))

        model.deletePhoto(id: photo.id)
        #expect(!FileManager.default.fileExists(atPath: imageFile(forPhotoID: photo.id).path))
        #expect(!model.hasStoredImage(forPhotoID: photo.id))
        #expect(try store.loadLibrary().photos.isEmpty)
        #expect(SampleData.model(store: store).photo(id: photo.id) == nil)
    }

    @Test func aDeletedSamplePhotoStaysDeletedWhenTheAppReopens() {
        let model = SampleData.model(store: store)
        model.deletePhoto(id: "b737-n823ak")

        let reopened = SampleData.model(store: store)
        #expect(reopened.photo(id: "b737-n823ak") == nil)
        #expect(reopened.photos.count == SampleData.photos.count - 1)
    }

    @Test func deletingTheAccountRemovesEveryPhotoAndImageFromTheDevice() throws {
        let model = SampleData.model(store: store)
        model.add(loggedPhoto(id: "imported-1"), image: tinyImage())
        model.add(loggedPhoto(id: "imported-2"), image: tinyImage())

        model.deleteAccountAndPhotos()
        #expect(model.photos.isEmpty)
        #expect(model.storageProblem == nil)
        #expect(!FileManager.default.fileExists(atPath: imageFile(forPhotoID: "imported-1").path))
        #expect(!FileManager.default.fileExists(atPath: imageFile(forPhotoID: "imported-2").path))
        #expect(try store.loadLibrary().photos.isEmpty)
        #expect(SampleData.model(store: store).photos.isEmpty)
    }

    // MARK: Problems

    @Test func aCollectionThatCannotBeReadIsLeftAsItIs() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let libraryFile = directory.appending(path: "library.json", directoryHint: .notDirectory)
        let unreadable = Data("not a library".utf8)
        try unreadable.write(to: libraryFile)

        let model = SampleData.model(store: store)
        #expect(model.storageProblem == .couldNotOpen)
        #expect(model.photos.count == SampleData.photos.count)

        // Nothing is saved this session, so the file is never written over.
        model.add(loggedPhoto(), image: tinyImage())
        #expect(try Data(contentsOf: libraryFile) == unreadable)
    }

    @Test func aPhotoIDThatCouldLeaveTheImagesFolderGetsNoFile() {
        #expect(throws: PhotoStoreError.self) {
            try store.saveImage(Data([1, 2, 3]), forPhotoID: "../outside")
        }
        #expect(store.imageData(forPhotoID: "../outside") == nil)
    }

    // MARK: Slots

    @Test func theSamplePhotosFillOneSlotForEachTypeAirlineAndRegistration() {
        let model = SampleData.model()
        #expect(model.slots(.aircraftType).count == 6)
        #expect(model.typesCollected == 6)
        #expect(model.slots(.airline).map(\.title) == [
            "Alaska Airlines", "Delta Connection", "US Air Force", "US Navy Blue Angels",
        ])
        #expect(model.slots(.registration).map(\.title) == ["29000", "N823AK"])
        #expect(model.slots(.livery).isEmpty)
    }

    @Test func anAirlineSlotKeepsItsBestShotAndListsTheRest() throws {
        let model = SampleData.model()
        let slot = try #require(model.slot(.airline, key: "us air force"))
        #expect(slot.bestPhotoID == "vc25a-29000")
        #expect(slot.tier == .gold)
        #expect(slot.photoIDs == ["vc25a-29000", "f22-raptor", "b2-spirit"])
        #expect(model.photos(in: slot).map(\.id) == slot.photoIDs)
    }

    @Test func aNewShotFillsItsRegistrationSlotAndLeavesTheTypeSlot() throws {
        let model = SampleData.model()
        model.add(loggedPhoto(id: "imported-max", type: "Boeing 737 MAX 8", registration: "N915AK", airline: "Alaska Airlines"))

        let type = try #require(model.slot(.aircraftType, key: "boeing 737 max 8"))
        #expect(type.bestPhotoID == "b737-n823ak")
        #expect(type.photoIDs == ["b737-n823ak", "imported-max"])
        #expect(model.slot(.registration, key: "n915ak")?.bestPhotoID == "imported-max")
        #expect(model.slot(.registration, key: "n823ak")?.bestPhotoID == "b737-n823ak")
    }

    @Test func aBlockedRegistrationNamesNoSlot() {
        let model = SampleData.model()
        let blocked = SpottedPhoto(
            id: "blocked",
            imageName: nil,
            aircraftType: "Gulfstream G650",
            registration: "N1AB",
            isRegistrationBlocked: true,
            airline: "",
            activity: "",
            status: .logged
        )
        model.add(blocked)
        #expect(model.slots(.registration).map(\.title) == ["29000", "N823AK"])
        #expect(model.slot(.aircraftType, key: "gulfstream g650") != nil)
    }

    @Test func deletingTheOnlyShotEmptiesItsSlot() {
        let model = SampleData.model()
        model.deletePhoto(id: "b737-n823ak")
        #expect(model.slot(.aircraftType, key: "boeing 737 max 8") == nil)
        #expect(model.slot(.registration, key: "n823ak") == nil)
    }

    // MARK: Spots

    @Test func aPhotoIsLinkedToTheNearestListedSpot() throws {
        let model = SampleData.model()
        let nearSouthApproach = try #require(Coordinate(latitude: 33.6220, longitude: -84.3995))
        #expect(model.nearestSpot(to: nearSouthApproach)?.id == "atl-south-approach")
    }

    @Test func aPhotoTakenFarFromEverySpotIsLinkedToNone() throws {
        let model = SampleData.model()
        let farAway = try #require(Coordinate(latitude: 40, longitude: -100))
        #expect(model.nearestSpot(to: farAway) == nil)
    }

    @Test func theMapPlacesEveryLocatedPhotoNewestFirst() {
        let model = SampleData.model()
        #expect(model.locatedPhotos.map(\.id) == ["vc25a-29000", "b2-spirit", "b737-n823ak"])

        // The owner sees their own undisclosed photo on their own map.
        model.add(loggedPhoto())
        #expect(model.locatedPhotos.first?.id == "imported-1")
        #expect(model.locatedPhotos.first?.ownerCaptureCoordinate != nil)
    }
}
