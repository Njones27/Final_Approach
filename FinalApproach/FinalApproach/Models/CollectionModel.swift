import FinalApproachCore
import Foundation
import Observation

/// The state every screen reads. It holds the user's photos, the spots, the
/// vote queue, and the tunable grading values.
///
/// The grading values are passed in so they can come from the backend later
/// without a release.
@Observable
final class CollectionModel {
    private(set) var photos: [SpottedPhoto]
    private(set) var profile: Profile
    private(set) var voteQueue: [VoteCandidate]
    /// How many photos were in today's vote set before any vote.
    let voteSetSize: Int
    let airports: [Airport]

    let thresholds: TierThresholds
    /// The lowest technical check score that counts as passed.
    let passingCheckScore: Double
    let gradeWeights: GradeWeights
    let votingRules: VotingRules
    let flightData: any FlightDataProvider

    init(
        photos: [SpottedPhoto],
        profile: Profile,
        voteQueue: [VoteCandidate],
        airports: [Airport],
        thresholds: TierThresholds,
        passingCheckScore: Double,
        gradeWeights: GradeWeights = .launch,
        votingRules: VotingRules = .launch,
        flightData: any FlightDataProvider
    ) {
        self.photos = photos
        self.profile = profile
        self.voteQueue = voteQueue
        voteSetSize = voteQueue.count
        self.airports = airports
        self.thresholds = thresholds
        self.passingCheckScore = passingCheckScore
        self.gradeWeights = gradeWeights
        self.votingRules = votingRules
        self.flightData = flightData
    }

    // MARK: Photos

    func photo(id: String) -> SpottedPhoto? {
        photos.first { $0.id == id }
    }

    /// The checks for a photo, sorted with the weakest first.
    func checkReport(for photo: SpottedPhoto) -> TechnicalCheckReport {
        TechnicalCheckReport(
            results: photo.findings.map(\.result),
            passingScore: passingCheckScore
        )
    }

    /// The technical check score, or nil when the check has not run.
    func technicalScore(for photo: SpottedPhoto) -> Double? {
        checkReport(for: photo).overallScore()
    }

    /// The final grade as a whole number, or nil until voting has closed.
    func finalScore(for photo: SpottedPhoto) -> Double? {
        guard case let .graded(voteAverage, _) = photo.status,
              let technical = technicalScore(for: photo)
        else { return nil }
        // The tier is set from the rounded grade, so the number on screen and
        // the tier beside it always agree.
        return FinalGrade.score(
            aiScore: technical,
            voteAverage: voteAverage,
            weights: gradeWeights,
            rules: votingRules
        )?.rounded()
    }

    /// The tier a photo holds. A photo with no final grade is `logged`.
    func tier(for photo: SpottedPhoto) -> Tier {
        guard let score = finalScore(for: photo) else { return .logged }
        return thresholds.tier(forScore: score)
    }

    /// The user's best graded photo, which leads the collection.
    var bestPhoto: SpottedPhoto? {
        var best: (photo: SpottedPhoto, score: Double)?
        for photo in photos {
            guard let score = finalScore(for: photo) else { continue }
            if let current = best, current.score >= score { continue }
            best = (photo, score)
        }
        return best?.photo
    }

    func add(_ photo: SpottedPhoto) {
        photos.insert(photo, at: 0)
    }

    /// Removes a photo. Once photos are stored on the device and the backend,
    /// this must also remove the stored images.
    func deletePhoto(id: String) {
        photos.removeAll { $0.id == id }
    }

    /// Removes the account's photos. Once accounts exist, this must also
    /// delete the account and every stored image.
    func deleteAccountAndPhotos() {
        photos.removeAll()
    }

    // MARK: Profile

    var typesCollected: Int {
        Set(photos.map(\.aircraftType)).count
    }

    var photosGraded: Int {
        photos.filter { finalScore(for: $0) != nil }.count
    }

    // MARK: Voting

    /// The photo waiting for a vote, or nil when today's set is finished.
    var currentVoteCandidate: VoteCandidate? {
        voteQueue.first
    }

    /// The position of the current photo in today's set, starting at 1.
    var votePosition: Int {
        voteSetSize - voteQueue.count + 1
    }

    /// Records a vote for the current photo and moves to the next one. A
    /// vote outside the scale is ignored.
    func castVote(_ vote: Int) {
        guard votingRules.isValid(vote: vote), !voteQueue.isEmpty else { return }
        voteQueue.removeFirst()
        profile.votesCast += 1
    }

    /// Moves to the next photo without voting.
    func skipVote() {
        guard !voteQueue.isEmpty else { return }
        voteQueue.removeFirst()
    }

    // MARK: Spots

    func spot(id: String) -> Spot? {
        for airport in airports {
            if let spot = airport.spots.first(where: { $0.id == id }) {
                return spot
            }
        }
        return nil
    }
}
