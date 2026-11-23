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
    /// The name of a sample image in the asset catalog. It is nil for a photo
    /// imported from the library, whose image the collection model holds.
    let imageName: String?
    let aircraftType: String
    /// The airline or operator, or an empty string when the user left it out.
    let airline: String
    /// A short phrase that follows the airline, such as "landing at Atlanta".
    /// It is empty when nothing is known.
    let activity: String
    /// The camera settings saved in the photo, when it carried any.
    let camera: CameraSettings?
    /// When the photo was taken, by the camera's clock.
    let capturedAt: Date?
    /// The id of the spot the photo was taken from, when one is known.
    let spotID: String?
    /// True when the owner chose to keep the location private. No other user
    /// may see where an undisclosed photo was taken.
    var isLocationUndisclosed: Bool
    var status: GradeStatus
    let findings: [CheckFinding]
    let fixes: [SuggestedFix]
    /// False when the technical check could not find an aircraft in the
    /// photo, so it had nothing to score.
    let isAircraftFound: Bool

    private let registration: String
    private let isRegistrationBlocked: Bool
    private let captureCoordinate: Coordinate?

    init(
        id: String,
        imageName: String?,
        aircraftType: String,
        registration: String,
        isRegistrationBlocked: Bool = false,
        airline: String,
        activity: String,
        camera: CameraSettings? = nil,
        capturedAt: Date? = nil,
        captureCoordinate: Coordinate? = nil,
        spotID: String? = nil,
        isLocationUndisclosed: Bool = false,
        status: GradeStatus,
        findings: [CheckFinding] = [],
        fixes: [SuggestedFix] = [],
        isAircraftFound: Bool = true
    ) {
        self.id = id
        self.imageName = imageName
        self.aircraftType = aircraftType
        self.registration = registration
        self.isRegistrationBlocked = isRegistrationBlocked
        self.airline = airline
        self.activity = activity
        self.camera = camera
        self.capturedAt = capturedAt
        self.captureCoordinate = captureCoordinate
        self.spotID = spotID
        self.isLocationUndisclosed = isLocationUndisclosed
        self.status = status
        self.findings = findings
        self.fixes = fixes
        self.isAircraftFound = isAircraftFound
    }

    /// The registration to show, or nil when there is none or the aircraft
    /// is on a block list such as FAA LADD. The stored value is private so no
    /// screen can show a blocked registration by accident.
    var visibleRegistration: String? {
        isRegistrationBlocked || registration.isEmpty ? nil : registration
    }

    /// The spot other people may see for this photo. It is nil for an
    /// undisclosed photo.
    var publicSpotID: String? {
        isLocationUndisclosed ? nil : spotID
    }

    /// Where the photo was taken, as other people may see it. It is nil for
    /// an undisclosed photo and for a photo with no saved location.
    var publicCaptureCoordinate: Coordinate? {
        isLocationUndisclosed ? nil : captureCoordinate
    }

    /// True when the photo carries a location, whether or not it is shared.
    var hasCaptureLocation: Bool {
        captureCoordinate != nil
    }

    /// The airline and the activity as one line, such as "Delta Air Lines,
    /// landing at Atlanta". It is nil when both are empty.
    var operatorLine: String? {
        let parts = [airline, activity].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// A description of the image for VoiceOver.
    var imageDescription: String {
        let subject = airline.isEmpty ? aircraftType : "\(airline) \(aircraftType)"
        return activity.isEmpty ? subject : "\(subject), \(activity)"
    }
}

/// A point on the map.
struct Coordinate: Equatable {
    let latitude: Double
    let longitude: Double

    /// Returns nil when either value is outside the range of a real place.
    init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
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
