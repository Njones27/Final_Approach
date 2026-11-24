import Foundation

/// A piece of text read off a photo.
public struct RecognizedText: Equatable, Sendable {
    public let text: String
    /// How sure the reader is of the text, from 0 to 1.
    public let confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

/// What follows the prefix of a registration.
public enum RegistrationSuffix: Equatable, Sendable, Codable {
    /// Letters only, such as the ABCD of G-ABCD. The range is how many.
    case letters(ClosedRange<Int>)
    /// Letters and numbers with at least one number, such as the 123A of
    /// JA123A. The range is how many characters.
    case lettersAndNumbers(ClosedRange<Int>)
    /// The United States rule. One to five characters that start with a
    /// number from 1 to 9, go on with numbers, and may end with one or two
    /// letters. The letters I and O are never used.
    case unitedStates
}

/// How one country writes its aircraft registrations.
///
/// The formats are data, so a country can be added or corrected without a
/// release.
public struct RegistrationFormat: Equatable, Sendable, Codable {
    public let country: String
    /// The letters every registration of this country starts with.
    public let prefix: String
    /// True when a hyphen is written after the prefix, as in G-ABCD.
    public let hasHyphen: Bool
    public let suffix: RegistrationSuffix

    public init(country: String, prefix: String, hasHyphen: Bool, suffix: RegistrationSuffix) {
        self.country = country
        self.prefix = prefix.uppercased()
        self.hasHyphen = hasHyphen
        self.suffix = suffix
    }

    /// The registration a piece of text spells in this format, written the
    /// standard way, or nil when the text is not one.
    ///
    /// A format with a hyphen needs the hyphen in the text. Without that
    /// rule a plain word such as DELTA would read as the German D-ELTA.
    public func registration(in token: String) -> String? {
        let text = token.uppercased()
        if hasHyphen {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == prefix else { return nil }
            guard let body = cleanSuffix(String(parts[1])) else { return nil }
            return "\(prefix)-\(body)"
        }
        guard text.hasPrefix(prefix), !text.contains("-") else { return nil }
        guard let body = cleanSuffix(String(text.dropFirst(prefix.count))) else { return nil }
        return prefix + body
    }

    /// The suffix when it follows this format's rule, or nil when it does
    /// not.
    private func cleanSuffix(_ text: String) -> String? {
        let characters = Array(text)
        guard characters.allSatisfy({ Self.isLetter($0) || Self.isNumber($0) }) else { return nil }
        switch suffix {
        case let .letters(count):
            guard count.contains(characters.count), characters.allSatisfy(Self.isLetter) else {
                return nil
            }
            return text
        case let .lettersAndNumbers(count):
            guard count.contains(characters.count), characters.contains(where: Self.isNumber) else {
                return nil
            }
            return text
        case .unitedStates:
            return Self.unitedStatesSuffix(characters)
        }
    }

    /// Checks the United States rule. A text reader often takes a zero for
    /// the letter O and a one for the letter I. Neither letter is used in
    /// these registrations, so they are read as the numbers. That is only
    /// done once the suffix has started with a real number, so a word such
    /// as NIKE is never read as N1KE.
    private static func unitedStatesSuffix(_ characters: [Character]) -> String? {
        guard (1...5).contains(characters.count), let first = characters.first else { return nil }
        guard isNumber(first), first != "0" else { return nil }
        let fixed = characters.map { character -> Character in
            switch character {
            case "O": "0"
            case "I": "1"
            default: character
            }
        }
        let numbers = fixed.prefix(while: isNumber)
        let letters = fixed.dropFirst(numbers.count)
        guard letters.count <= 2, letters.allSatisfy(isLetter) else { return nil }
        return String(fixed)
    }

    private static func isLetter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
    }

    private static func isNumber(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}

/// A registration found in the text read off a photo.
public struct RegistrationReading: Equatable, Sendable, Identifiable {
    /// The registration written the standard way, such as G-ABCD.
    public let registration: String
    public let country: String
    /// How sure the text reader was, from 0 to 1.
    public let confidence: Double

    public var id: String { registration }

    public init(registration: String, country: String, confidence: Double) {
        self.registration = registration
        self.country = country
        self.confidence = confidence
    }
}

/// Finds aircraft registrations in the text read off a photo.
public enum RegistrationReader {
    /// The registrations in the text, surest first. A registration that
    /// was read more than once is listed once with its best confidence.
    public static func readings(
        in texts: [RecognizedText],
        formats: [RegistrationFormat]
    ) -> [RegistrationReading] {
        var readings: [RegistrationReading] = []
        for text in texts {
            for token in tokens(in: text.text) {
                guard let match = firstMatch(for: token, formats: formats) else { continue }
                if let index = readings.firstIndex(where: { $0.registration == match.registration }) {
                    if readings[index].confidence < text.confidence {
                        readings[index] = RegistrationReading(
                            registration: match.registration,
                            country: match.country,
                            confidence: text.confidence
                        )
                    }
                } else {
                    readings.append(
                        RegistrationReading(
                            registration: match.registration,
                            country: match.country,
                            confidence: text.confidence
                        )
                    )
                }
            }
        }
        // The sort keeps the order they were read in for equal confidence.
        return readings.enumerated()
            .sorted { first, second in
                if first.element.confidence != second.element.confidence {
                    return first.element.confidence > second.element.confidence
                }
                return first.offset < second.offset
            }
            .map(\.element)
    }

    private static func firstMatch(
        for token: String,
        formats: [RegistrationFormat]
    ) -> (registration: String, country: String)? {
        for format in formats {
            if let registration = format.registration(in: token) {
                return (registration, format.country)
            }
        }
        return nil
    }

    /// Splits text into the runs of letters, numbers, and hyphens that
    /// could each be a registration. Every kind of dash counts as a hyphen.
    static func tokens(in text: String) -> [String] {
        let dashes: Set<Character> = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"]
        var tokens: [String] = []
        var current = ""
        for character in text.uppercased() {
            if dashes.contains(character) {
                current.append("-")
            } else if character.isASCII, character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
            .filter { !$0.isEmpty }
    }
}

/// The registrations whose identity must stay hidden, such as aircraft on
/// the FAA LADD list.
public struct RegistrationBlockList: Equatable, Sendable {
    private let keys: Set<String>

    public static let empty = RegistrationBlockList(registrations: [])

    public init(registrations: [String]) {
        keys = Set(registrations.map { CollectionBook.key(for: $0, kind: .registration) })
    }

    /// True when the registration is on the list. Case, spaces, and
    /// hyphens are ignored.
    public func contains(_ registration: String) -> Bool {
        let key = CollectionBook.key(for: registration, kind: .registration)
        return !key.isEmpty && keys.contains(key)
    }
}
