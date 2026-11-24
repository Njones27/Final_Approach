import Foundation

/// A short line of text that other people read beside a photo, such as an
/// aircraft type or an airline on a spot's page.
///
/// The backend keeps the same rule and refuses a line that breaks it. So
/// a line that would be refused is left out here, and the photo is still
/// shown.
public enum ShownText {
    /// The line as it may be shown, or nil when there is nothing to show.
    ///
    /// The text is trimmed. An empty line, a line longer than `maxLength`,
    /// and a line that holds a control character all give nil.
    ///
    /// - Parameter maxLength: The most characters a line may hold, counted
    ///   as the backend counts them, in UTF-16 units.
    public static func line(from text: String, maxLength: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf16.count <= maxLength else { return nil }
        // A control character has no place in a name and can hide what
        // follows it.
        let hasControl = trimmed.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        return hasControl ? nil : trimmed
    }
}
