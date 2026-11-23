import Foundation

/// What the Add screen does with the location of a new photo.
enum LocationPrivacySetting: String, CaseIterable, Identifiable {
    case askEachTime
    case alwaysShow
    case alwaysHide

    /// The key this setting is saved under in user defaults.
    static let storageKey = "locationPrivacy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .askEachTime: "Ask each time"
        case .alwaysShow: "Show the spot"
        case .alwaysHide: "Hide the spot"
        }
    }

    /// Whether the switch on the Add screen starts on. The user can still
    /// change it for each photo.
    var showsSpotByDefault: Bool {
        self != .alwaysHide
    }
}
