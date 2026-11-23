import FinalApproachCore
import Testing
import UIKit

@testable import FinalApproach

@MainActor
struct CollectionModelTests {
    let model = SampleData.model()

    @Test func blendsTheTechnicalCheckAndVotesIntoAWholeNumberGrade() throws {
        let photo = try #require(model.photo(id: "a350-n502dn"))
        #expect(model.technicalScore(for: photo) == 78)
        #expect(model.finalScore(for: photo) == 83)
    }

    @Test func everySampleGradeMatchesTheDesign() throws {
        let expected = [
            "b748-n605up": 88.0,
            "a350-n502dn": 83.0,
            "b737-n8642e": 71.0,
            "e175-n620qx": 66.0,
            "b787-n27965": 58.0,
        ]
        for (id, grade) in expected {
            let photo = try #require(model.photo(id: id))
            #expect(model.finalScore(for: photo) == grade)
        }
    }

    @Test func aPhotoStillInVotingHasNoGrade() throws {
        let photo = try #require(model.photo(id: "a220-n3008j"))
        #expect(model.finalScore(for: photo) == nil)
    }

    @Test func theBestGradedPhotoLeadsTheCollection() {
        #expect(model.bestPhoto?.id == "b748-n605up")
    }

    @Test func aBlockedRegistrationIsNeverShown() {
        let photo = SpottedPhoto(
            id: "blocked",
            imageName: "SampleA350",
            aircraftType: "Gulfstream G650",
            registration: "N1AB",
            isRegistrationBlocked: true,
            airline: "Private owner",
            activity: "landing",
            status: .logged
        )
        #expect(photo.visibleRegistration == nil)
    }

    @Test func anUndisclosedPhotoHasNoPublicSpot() {
        var photo = SpottedPhoto(
            id: "private",
            imageName: "SampleA350",
            aircraftType: "Airbus A350-900",
            registration: "N502DN",
            airline: "Delta Air Lines",
            activity: "landing",
            spotID: "atl-south-approach",
            status: .logged
        )
        #expect(photo.publicSpotID == "atl-south-approach")
        photo.isLocationUndisclosed = true
        #expect(photo.publicSpotID == nil)
    }

    @Test func aPhotoWithNoRegistrationShowsNone() {
        let photo = SpottedPhoto(
            id: "no-registration",
            imageName: nil,
            aircraftType: "Cessna 172",
            registration: "",
            airline: "",
            activity: "",
            status: .logged
        )
        #expect(photo.visibleRegistration == nil)
        #expect(photo.operatorLine == nil)
        #expect(photo.imageDescription == "Cessna 172")
    }

    @Test func theOperatorLineJoinsWhatIsKnown() throws {
        let sample = try #require(model.photo(id: "a350-n502dn"))
        #expect(sample.operatorLine == "Delta Air Lines, landing at Atlanta")
        #expect(sample.imageDescription == "Delta Air Lines Airbus A350-900, landing at Atlanta")
    }

    @Test func anUndisclosedPhotoSharesNoCoordinate() throws {
        let coordinate = try #require(Coordinate(latitude: 33.6215, longitude: -84.399))
        var photo = SpottedPhoto(
            id: "private-coordinate",
            imageName: nil,
            aircraftType: "Airbus A350-900",
            registration: "N502DN",
            airline: "Delta Air Lines",
            activity: "",
            captureCoordinate: coordinate,
            status: .logged
        )
        #expect(photo.hasCaptureLocation)
        #expect(photo.publicCaptureCoordinate?.latitude == 33.6215)
        photo.isLocationUndisclosed = true
        #expect(photo.hasCaptureLocation)
        #expect(photo.publicCaptureCoordinate?.latitude == nil)
    }

    @Test func aCoordinateOutsideTheGlobeIsRejected() {
        #expect(Coordinate(latitude: 91, longitude: 0) == nil)
        #expect(Coordinate(latitude: 0, longitude: -181) == nil)
        #expect(Coordinate(latitude: -90, longitude: 180) != nil)
    }

    @Test func deletingAnImportedPhotoRemovesItsStoredImage() {
        let photo = SpottedPhoto(
            id: "imported",
            imageName: nil,
            aircraftType: "Boeing 737-800",
            registration: "N8642E",
            airline: "Southwest Airlines",
            activity: "",
            status: .logged
        )
        model.add(photo, image: UIImage())
        #expect(model.photos.first?.id == "imported")
        #expect(model.hasStoredImage(forPhotoID: "imported"))
        model.deletePhoto(id: "imported")
        #expect(!model.hasStoredImage(forPhotoID: "imported"))
    }

    @Test func deletingTheAccountRemovesStoredImages() {
        let photo = SpottedPhoto(
            id: "imported",
            imageName: nil,
            aircraftType: "Boeing 737-800",
            registration: "",
            airline: "",
            activity: "",
            status: .logged
        )
        model.add(photo, image: UIImage())
        model.deleteAccountAndPhotos()
        #expect(!model.hasStoredImage(forPhotoID: "imported"))
    }

    @Test func deletingAPhotoRemovesItFromTheCollection() {
        model.deletePhoto(id: "a350-n502dn")
        #expect(model.photo(id: "a350-n502dn")?.id == nil)
        #expect(model.photos.count == 5)
    }

    @Test func deletingTheAccountRemovesEveryPhoto() {
        model.deleteAccountAndPhotos()
        #expect(model.photos.isEmpty)
        #expect(model.bestPhoto?.id == nil)
    }

    @Test func theTechnicalCheckNamesWhatToFixWeakestFirst() {
        let check = model.technicalCheck(for: SampleData.softBrightMeasurements, camera: nil)
        #expect(check.findings.count == 3)
        #expect(check.fixes.map(\.title) == ["Check focus and shutter speed", "Lower the exposure"])
        #expect(check.fixes.map(\.detail) == ["The aircraft is soft.", "Bright parts of the aircraft lose detail."])
        #expect(check.fixes.map(\.points) == [5, 4])
    }

    @Test func aPhotoWithNothingMeasuredHasNoCheck() {
        let check = model.technicalCheck(for: .none, camera: nil)
        #expect(check.findings.isEmpty)
        #expect(check.fixes.isEmpty)
    }

    @Test func aCheckedPhotoHasATechnicalScoreAndNoGrade() {
        let photo = SampleData.checkedPhoto(in: model)
        model.add(photo)
        #expect(model.technicalScore(for: photo)?.rounded() == 59)
        #expect(model.finalScore(for: photo) == nil)
        // 1/2000 s freezes an aircraft, so the shutter is not blamed.
        #expect(photo.fixes.first?.title == "Check focus and haze")
        #expect(photo.fixes.first?.detail == "The aircraft is soft at 1/2000 s.")
    }

    @Test func aPhotoWithNoAircraftFoundIsNotScored() {
        let photo = SampleData.unfoundPhoto
        model.add(photo)
        #expect(!photo.isAircraftFound)
        #expect(model.technicalScore(for: photo) == nil)
        #expect(!model.checkReport(for: photo).isPassed)
    }

    @Test func aVoteMovesToTheNextPhotoAndCounts() {
        let firstID = model.currentVoteCandidate?.id
        let votesBefore = model.profile.votesCast
        model.castVote(4)
        #expect(model.currentVoteCandidate?.id != firstID)
        #expect(model.votePosition == 2)
        #expect(model.profile.votesCast == votesBefore + 1)
    }

    @Test func aVoteOutsideTheScaleIsIgnored() {
        let firstID = model.currentVoteCandidate?.id
        model.castVote(6)
        #expect(model.currentVoteCandidate?.id == firstID)
        #expect(model.votePosition == 1)
    }

    @Test func skippingMovesOnWithoutCountingAVote() {
        let votesBefore = model.profile.votesCast
        model.skipVote()
        #expect(model.votePosition == 2)
        #expect(model.profile.votesCast == votesBefore)
    }

    @Test func theVoteSetEndsAfterTheLastPhoto() {
        for _ in 0..<model.voteSetSize {
            model.castVote(3)
        }
        #expect(model.currentVoteCandidate?.id == nil)
    }
}
