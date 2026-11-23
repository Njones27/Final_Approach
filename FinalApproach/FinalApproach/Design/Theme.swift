import FinalApproachCore
import SwiftUI
import UIKit

/// The Darkroom look. Every color has a dark and a light value under one
/// name, so a screen never branches on the color scheme.
enum Theme {
    /// The screen background. True black in dark mode so photos lead.
    static let ground = Color.dynamic(light: 0xFFFFFF, dark: 0x000000)
    /// A raised surface such as a card on the map.
    static let surface = Color.dynamic(light: 0xF2F2F5, dark: 0x1C1C1E)
    static let hairline = Color.dynamic(light: 0xE3E3E8, dark: 0x2A2A2E)
    /// Primary text and the fill of the primary button.
    static let ink = Color.dynamic(light: 0x0B0B0F, dark: 0xFFFFFF)
    static let secondaryText = Color.dynamic(light: 0x5F5F68, dark: 0xB4B4BC)
    static let chevron = Color.dynamic(light: 0xA9A9B2, dark: 0x8E8E96)
    /// The quiet fill behind secondary buttons and selected controls.
    static let controlFill = Color.dynamic(light: 0x0B0B0F, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.14)
    /// The empty part of a meter and the logged part of the tier scale.
    static let track = Color.dynamic(light: 0xD9D9E0, dark: 0x3A3A40)

    /// Text that sits on a photo. It is white in both appearances because the
    /// scrim under it is always dark.
    static let onPhoto = Color.white
    /// The dark wash under labels on a photo, and the color of shadows.
    static let scrim = Color.black
    /// The on color of a switch. The app tint is black or white, which would
    /// hide the knob, so switches use the system green.
    static let switchOn = Color.green

    /// The fill for a tier, used for dots, meters, and the tier scale.
    static func fill(for tier: Tier) -> Color {
        switch tier {
        case .logged: track
        case .bronze: Color.dynamic(light: 0xC07A46, dark: 0xD29A6C)
        case .silver: Color.dynamic(light: 0xA3ABB6, dark: 0xC9CED6)
        case .gold: Color.dynamic(light: 0xD4A21C, dark: 0xE8C15A)
        }
    }

    /// The text color for a tier name. It is deeper than the fill in light
    /// mode so it stays readable on white.
    static func text(for tier: Tier) -> Color {
        switch tier {
        case .logged: secondaryText
        case .bronze: Color.dynamic(light: 0x8F5226, dark: 0xD29A6C)
        case .silver: Color.dynamic(light: 0x5C6470, dark: 0xC9CED6)
        case .gold: Color.dynamic(light: 0x8A6100, dark: 0xF0CC6A)
        }
    }

    /// The color for points a fix would add.
    static let gain = text(for: .gold)
}

extension Color {
    /// A color that follows the light or dark appearance. Values are RGB hex
    /// numbers such as `0x1C1C1E`.
    nonisolated static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: Double = 1,
        darkAlpha: Double = 1
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            let alpha = isDark ? darkAlpha : lightAlpha
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(alpha)
            )
        })
    }
}

extension Font {
    /// The weights of the bundled condensed face.
    enum CondensedWeight {
        case medium
        case semibold

        var fontName: String {
            switch self {
            case .medium: "BarlowCondensed-Medium"
            case .semibold: "BarlowCondensed-SemiBold"
            }
        }
    }

    /// Barlow Condensed, used only for grade numbers, registrations, and
    /// counts. Everything else is the system font. The size scales with the
    /// reader's text size setting.
    static func condensed(
        _ size: CGFloat,
        weight: CondensedWeight = .semibold,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .custom(weight.fontName, size: size, relativeTo: textStyle)
    }
}
