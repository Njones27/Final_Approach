import SwiftUI

/// Whether the app follows the iPhone appearance or stays light or dark.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// The key this setting is saved under in user defaults.
    static let storageKey = "appearance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The color scheme to force, or nil to follow the iPhone setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
