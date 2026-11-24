import FinalApproachCore
import Foundation
import Testing

@testable import FinalApproach

/// A photo logged without naming the aircraft, and naming it later.
@MainActor
final class UnknownAircraftTests {
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
        id: String = "imported-unknown",
        type: String = "",
        registration: String = "",
        isRegistrationBlocked: Bool = false,
        airline: String = ""
    ) -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: type,
            registration: registration,
            isRegistrationBlocked: isRegistrationBlocked,
            airline: airline,
            activity: "",
            loggedAt: Date(timeIntervalSince1970: 1_800_000_000),
            captureCoordinate: Coordinate(latitude: 33.6220, longitude: -84.3995),
            spotID: "atl-south-approach",
            isLocationUndisclosed: true,
            status: .logged
        )
    }

    // MARK: Logging with no type

    @Test func aPhotoWithNoTypeSaysTheAircraftIsUnknown() {
        let photo = loggedPhoto()
        #expect(!photo.isTypeKnown)
        #expect(photo.typeTitle == "Unknown aircraft")
        #expect(photo.imageDescription == "Unknown aircraft")
        #expect(loggedPhoto(airline: "Delta Air Lines").imageDescription == "Delta Air Lines aircraft")
    }

    @Test func aPhotoWithATypeShowsIt() {
        let photo = loggedPhoto(type: "Boeing 737-800", airline: "Southwest Airlines")
        #expect(photo.isTypeKnown)
        #expect(photo.typeTitle == "Boeing 737-800")
        #expect(photo.imageDescription == "Southwest Airlines Boeing 737-800")
    }

    @Test func aPhotoWithNoTypeFillsNoTypeSlotButIsStillListed() {
        let model = SampleData.model()
        let typesBefore = model.slots(.aircraftType).count
        model.add(loggedPhoto())

        #expect(model.slots(.aircraftType).count == typesBefore)
        #expect(model.typesCollected == typesBefore)
        #expect(model.unidentifiedPhotos.map(\.id) == ["imported-unknown"])
        #expect(model.photo(id: "imported-unknown") != nil)
    }

    @Test func theSamplePhotosAllHaveATypeSoNoneIsListedAsUnknown() {
        #expect(SampleData.model().unidentifiedPhotos.isEmpty)
    }

    // MARK: Naming it later

    @Test func namingTheAircraftLaterFillsItsSlotsAndIsSaved() throws {
        let model = SampleData.model(store: store)
        model.add(loggedPhoto())
        model.updateDetails(
            forPhotoID: "imported-unknown",
            aircraftType: "  Airbus A320  ",
            registration: " n123ab ",
            airline: " JetBlue "
        )
        #expect(model.storageProblem == nil)

        let named = try #require(model.photo(id: "imported-unknown"))
        #expect(named.aircraftType == "Airbus A320")
        #expect(named.visibleRegistration == "N123AB")
        #expect(named.airline == "JetBlue")
        #expect(model.unidentifiedPhotos.isEmpty)
        #expect(model.slots(.aircraftType).contains { $0.title == "Airbus A320" })

        let reopened = try #require(SampleData.model(store: store).photo(id: "imported-unknown"))
        #expect(reopened == named)
    }

    @Test func anEditKeepsEverythingElseAboutThePhoto() throws {
        let model = SampleData.model()
        let photo = loggedPhoto()
        model.add(photo)
        model.updateDetails(forPhotoID: photo.id, aircraftType: "Airbus A320", registration: "", airline: "")

        let edited = try #require(model.photo(id: photo.id))
        #expect(edited.loggedAt == photo.loggedAt)
        #expect(edited.ownerCaptureCoordinate == photo.ownerCaptureCoordinate)
        #expect(edited.spotID == photo.spotID)
        #expect(edited.isLocationUndisclosed)
        #expect(edited.publicCaptureCoordinate == nil)
        #expect(edited.status == photo.status)
    }

    @Test func aRegistrationOnTheBlockListStaysHiddenAfterAnEdit() throws {
        let model = SampleData.model(blockList: RegistrationBlockList(registrations: ["N123AB"]))
        model.add(loggedPhoto())
        model.updateDetails(forPhotoID: "imported-unknown", aircraftType: "", registration: "n123ab", airline: "")

        let edited = try #require(model.photo(id: "imported-unknown"))
        #expect(edited.visibleRegistration == nil)
        #expect(edited.hasBlockedRegistration)
        #expect(model.slots(.registration).allSatisfy { $0.key != "n123ab" })
    }

    @Test func anEditThatNeverShowedABlockedRegistrationKeepsIt() throws {
        let model = SampleData.model()
        model.add(loggedPhoto(registration: "N123AB", isRegistrationBlocked: true))
        // The edit screen leaves out the field, and passes nil for it.
        model.updateDetails(forPhotoID: "imported-unknown", aircraftType: "Gulfstream G650", registration: nil, airline: "")

        let edited = try #require(model.photo(id: "imported-unknown"))
        #expect(edited.aircraftType == "Gulfstream G650")
        #expect(edited.hasBlockedRegistration)
        #expect(edited.visibleRegistration == nil)
    }

    @Test func aSamplePhotoIsNotChanged() throws {
        let model = SampleData.model()
        let sample = try #require(model.photos.first { $0.isSample })
        model.updateDetails(forPhotoID: sample.id, aircraftType: "Something else", registration: "", airline: "")
        #expect(model.photo(id: sample.id) == sample)
    }
}
