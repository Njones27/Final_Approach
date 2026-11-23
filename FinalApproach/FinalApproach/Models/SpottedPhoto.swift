import FinalApproachCore
import Foundation

/// Where a photo is in the grading process.
enum GradeStatus {
    /// Logged, with no grade yet.
    case logged
    /// Open for community votes.
    case voting(votesIn: Int, hoursLeft: Int)
    /// Voting closed with enough votes.
    case graded(voteAverage: Double, voteCount: Int)
}

/// One finding from the technical check, written for the photographer.
struct CheckFinding: Identifiable {
    let result: CheckResult
    /// What the check saw, and how to fix it when it needs work.
    let detail: String

    var id: CheckKind { result.kind }
}

/// A fix that would raise the grade, with the points it is worth.
struct SuggestedFix: Identifiable {
    let kind: CheckKind
    /// A verb and an object, such as "Straighten the horizon".
    let title: String
    let detail: String
    let points: Int

    var id: CheckKind { kind }
}

/// One photo of one aircraft in the user's collection.
struct SpottedPhoto: Identifiable {
    let id: String
    /// The name of the image in the asset catalog. Imported photos replace
    /// this with a file reference in the import milestone.
    let imageName: String
    let aircraftType: String
    let airline: String
    /// A short phrase that follows the airline, such as "landing at Atlanta".
    let activity: String
    /// The id of the spot the photo was taken from, when one is known.
    let spotID: String?
    /// True when the owner chose to keep the location private. No other user
    /// may see where an undisclosed photo was taken.
    var isLocationUndisclosed: Bool
    var status: GradeStatus
    let findings: [CheckFinding]
    let fixes: [SuggestedFix]

    private let registration: String
    private let isRegistrationBlocked: Bool

    init(
        id: String,
        imageName: String,
        aircraftType: String,
        registration: String,
        isRegistrationBlocked: Bool = false,
        airline: String,
        activity: String,
        spotID: String? = nil,
        isLocationUndisclosed: Bool = false,
        status: GradeStatus,
        findings: [CheckFinding] = [],
        fixes: [SuggestedFix] = []
    ) {
        self.id = id
        self.imageName = imageName
        self.aircraftType = aircraftType
        self.registration = registration
        self.isRegistrationBlocked = isRegistrationBlocked
        self.airline = airline
        self.activity = activity
        self.spotID = spotID
        self.isLocationUndisclosed = isLocationUndisclosed
        self.status = status
        self.findings = findings
        self.fixes = fixes
    }

    /// The registration to show, or nil when the aircraft is on a block list
    /// such as FAA LADD. The stored value is private so no screen can show a
    /// blocked registration by accident.
    var visibleRegistration: String? {
        isRegistrationBlocked ? nil : registration
    }

    /// The spot other people may see for this photo. It is nil for an
    /// undisclosed photo.
    var publicSpotID: String? {
        isLocationUndisclosed ? nil : spotID
    }

    /// A description of the image for VoiceOver.
    var imageDescription: String {
        "\(airline) \(aircraftType), \(activity)"
    }
}

/// A place to photograph aircraft from.
struct Spot: Identifiable {
    let id: String
    let name: String
    let summary: String
    let latitude: Double
    let longitude: Double
    /// How many photos other people have shared from this spot.
    let photoCount: Int
    /// Asset names of a few shared photos from this spot. Only photos whose
    /// owners disclosed the location may appear here.
    let photoNames: [String]
}

/// An airport and the spots around it.
struct Airport: Identifiable {
    /// The IATA code, such as "ATL".
    let id: String
    let city: String
    let latitude: Double
    let longitude: Double
    let spots: [Spot]

    var displayName: String { "\(city), \(id)" }
}

/// The signed-in photographer.
struct Profile {
    let name: String
    let memberSince: String
    var votesCast: Int
    let level: Int
    let experience: Int
    let experienceForNextLevel: Int
    /// How much this person's votes count, earned by voting close to final
    /// grades.
    let voteWeight: Double

    var experienceToNextLevel: Int { max(experienceForNextLevel - experience, 0) }
}

/// A photo from another photographer that is waiting for this user's vote.
/// It carries no photographer and no score, so neither can sway the vote.
struct VoteCandidate: Identifiable {
    let id: String
    let imageName: String
    let aircraftType: String
}
