import FinalApproachCore
import Foundation

/// Where a photo is in the grading process, as it is saved with the photo.
/// A photo the user logged is saved as `logged`, and what the backend says
/// about its post is kept apart from it. The screens read `PhotoProgress`.
enum GradeStatus: Equatable, Codable {
    /// Logged, with no grade yet.
    case logged
    /// Open for community votes.
    case voting(votesIn: Int, hoursLeft: Int)
    /// Voting closed with enough votes.
    case graded(voteAverage: Double, voteCount: Int)
}

/// Where a photo is on its way to a grade, as its owner's screens show it.
///
/// A photo the user posted takes this from the backend's word on its post.
/// A sample photo takes it from its own `status`.
enum PhotoProgress: Equatable {
    /// Not posted. Nobody else has seen the photo.
    case logged
    /// Posted and open for votes. `hoursLeft` is 0 once the voting window
    /// has ended, and the photo then stays open until `votesNeeded` more
    /// votes arrive.
    case voting(votesIn: Int, votesNeeded: Int, hoursLeft: Int)
    /// The votes have set the grade, from 0 to 100.
    case graded(score: Double, voteCount: Int)

    /// True once the photo is in front of other users, or was.
    var isPosted: Bool { self != .logged }
}

/// One finding from the technical check, written for the photographer.
struct CheckFinding: Identifiable, Equatable, Codable {
    let result: CheckResult
    /// What the check saw, and how to fix it when it needs work.
    let detail: String

    var id: CheckKind { result.kind }
}

/// A fix that would raise the technical reading, with the points of that
/// reading it is worth. It is advice, and the grade does not depend on it.
struct SuggestedFix: Identifiable, Equatable, Codable {
    let kind: CheckKind
    /// A verb and an object, such as "Straighten the horizon".
    let title: String
    let detail: String
    let points: Int

    var id: CheckKind { kind }
}

/// One photo of one aircraft in the user's collection.
///
/// It is `Codable` so a logged photo can be saved on the device. A new
/// stored property needs a default when it is read from an older file.
struct SpottedPhoto: Identifiable, Equatable, Codable {
    let id: String
    /// The name of a sample image in the asset catalog. It is nil for a photo
    /// imported from the library, whose image is saved on the device.
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
    /// When the photo joined the collection. The collection fills its slots
    /// in this order.
    let loggedAt: Date
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
        loggedAt: Date? = nil,
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
        // A photo with no logging time counts from when it was taken.
        self.loggedAt = loggedAt ?? capturedAt ?? Date(timeIntervalSince1970: 0)
        self.captureCoordinate = captureCoordinate
        self.spotID = spotID
        self.isLocationUndisclosed = isLocationUndisclosed
        self.status = status
        self.findings = findings
        self.fixes = fixes
        self.isAircraftFound = isAircraftFound
    }

    /// What stands in for the type of an aircraft the user could not name.
    static let unknownAircraftName = "Unknown aircraft"

    /// False for a photo logged without an aircraft type.
    var isTypeKnown: Bool {
        !aircraftType.isEmpty
    }

    /// The aircraft type to show. A photo logged without one says so.
    var typeTitle: String {
        isTypeKnown ? aircraftType : Self.unknownAircraftName
    }

    /// The same photo with new aircraft details. Passing nil for the
    /// registration keeps the stored one, which is how a blocked
    /// registration survives an edit that never showed it.
    func replacingDetails(
        aircraftType: String,
        registration: String?,
        isRegistrationBlocked: Bool?,
        airline: String
    ) -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: imageName,
            aircraftType: aircraftType,
            registration: registration ?? self.registration,
            isRegistrationBlocked: isRegistrationBlocked ?? self.isRegistrationBlocked,
            airline: airline,
            activity: activity,
            camera: camera,
            capturedAt: capturedAt,
            loggedAt: loggedAt,
            captureCoordinate: captureCoordinate,
            spotID: spotID,
            isLocationUndisclosed: isLocationUndisclosed,
            status: status,
            findings: findings,
            fixes: fixes,
            isAircraftFound: isAircraftFound
        )
    }

    /// True when the photo holds a registration that must stay hidden.
    var hasBlockedRegistration: Bool {
        isRegistrationBlocked && !registration.isEmpty
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

    /// Where the photo was taken, for the owner's own screens. It is set
    /// even when the photo is undisclosed, so nothing shown to another
    /// person may read it. Those screens use `publicCaptureCoordinate`.
    var ownerCaptureCoordinate: Coordinate? {
        captureCoordinate
    }

    /// True for one of the sample photos that ship with the app.
    var isSample: Bool {
        imageName != nil
    }

    /// What this photo offers the collection. A blocked registration is
    /// left out, so it never names a slot.
    func slotShot(score: Double?, technicalReading: Double? = nil) -> SlotShot {
        SlotShot(
            photoID: id,
            aircraftType: aircraftType,
            airline: airline,
            registration: visibleRegistration ?? "",
            score: score,
            technicalReading: technicalReading,
            loggedAt: loggedAt
        )
    }

    /// The airline and the activity as one line, such as "Delta Air Lines,
    /// landing at Atlanta". It is nil when both are empty.
    var operatorLine: String? {
        let parts = [airline, activity].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// A description of the image for VoiceOver.
    var imageDescription: String {
        // An aircraft with no type is "Unknown aircraft", or "Delta Air
        // Lines aircraft" when the airline is known.
        let subject: String
        if airline.isEmpty {
            subject = typeTitle
        } else {
            subject = isTypeKnown ? "\(airline) \(aircraftType)" : "\(airline) aircraft"
        }
        return activity.isEmpty ? subject : "\(subject), \(activity)"
    }
}

/// A point on the map. The core package owns the type, so distances can be
/// worked out and tested there.
typealias Coordinate = GeoPoint

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

    var coordinate: Coordinate? {
        Coordinate(latitude: latitude, longitude: longitude)
    }
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
