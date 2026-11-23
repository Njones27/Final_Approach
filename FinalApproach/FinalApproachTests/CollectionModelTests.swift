import Testing

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
