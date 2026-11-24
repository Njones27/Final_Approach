import Testing

@testable import FinalApproachCore

private let unitedStates = RegistrationFormat(
    country: "United States", prefix: "N", hasHyphen: false, suffix: .unitedStates
)
private let unitedKingdom = RegistrationFormat(
    country: "United Kingdom", prefix: "G", hasHyphen: true, suffix: .letters(4...4)
)
private let germany = RegistrationFormat(
    country: "Germany", prefix: "D", hasHyphen: true, suffix: .letters(4...4)
)
private let japan = RegistrationFormat(
    country: "Japan", prefix: "JA", hasHyphen: false, suffix: .lettersAndNumbers(4...4)
)
private let china = RegistrationFormat(
    country: "China", prefix: "B", hasHyphen: true, suffix: .lettersAndNumbers(4...4)
)
private let formats = [unitedStates, unitedKingdom, germany, japan, china]

private func read(_ lines: String...) -> [String] {
    let texts = lines.map { RecognizedText(text: $0, confidence: 0.9) }
    return RegistrationReader.readings(in: texts, formats: formats).map(\.registration)
}

@Suite struct RegistrationFormatTests {
    @Test func readsUnitedStatesRegistrations() {
        #expect(unitedStates.registration(in: "N823AK") == "N823AK")
        #expect(unitedStates.registration(in: "n1") == "N1")
        #expect(unitedStates.registration(in: "N12345") == "N12345")
        #expect(unitedStates.registration(in: "N1234Z") == "N1234Z")
        #expect(unitedStates.registration(in: "N123AB") == "N123AB")
    }

    @Test func rejectsWhatBreaksTheUnitedStatesRule() {
        // Too long, a leading zero, three letters, and a number after a letter.
        #expect(unitedStates.registration(in: "N123456") == nil)
        #expect(unitedStates.registration(in: "N0123") == nil)
        #expect(unitedStates.registration(in: "N1ABC") == nil)
        #expect(unitedStates.registration(in: "N1A2") == nil)
        #expect(unitedStates.registration(in: "N") == nil)
        #expect(unitedStates.registration(in: "N-123") == nil)
    }

    @Test func plainWordsAreNotUnitedStatesRegistrations() {
        #expect(unitedStates.registration(in: "NIKE") == nil)
        #expect(unitedStates.registration(in: "NOW") == nil)
        #expect(unitedStates.registration(in: "NAVY") == nil)
        #expect(unitedStates.registration(in: "NINE") == nil)
    }

    @Test func readsAMisreadLetterAsItsNumber() {
        // The letters O and I are never used, so they were numbers.
        #expect(unitedStates.registration(in: "N8O3AK") == "N803AK")
        #expect(unitedStates.registration(in: "N2I5") == "N215")
    }

    @Test func aHyphenFormatNeedsItsHyphen() {
        #expect(unitedKingdom.registration(in: "G-ABCD") == "G-ABCD")
        #expect(unitedKingdom.registration(in: "g-abcd") == "G-ABCD")
        #expect(unitedKingdom.registration(in: "GABCD") == nil)
        #expect(germany.registration(in: "DELTA") == nil)
        #expect(germany.registration(in: "D-AIMA") == "D-AIMA")
    }

    @Test func checksTheSuffixOfAHyphenFormat() {
        #expect(unitedKingdom.registration(in: "G-ABC") == nil)
        #expect(unitedKingdom.registration(in: "G-ABCDE") == nil)
        #expect(unitedKingdom.registration(in: "G-AB1D") == nil)
        #expect(unitedKingdom.registration(in: "G-AB-CD") == nil)
        #expect(unitedKingdom.registration(in: "D-ABCD") == nil)
    }

    @Test func aSuffixOfLettersAndNumbersNeedsANumber() {
        #expect(japan.registration(in: "JA873A") == "JA873A")
        #expect(japan.registration(in: "JAPAN") == nil)
        #expect(japan.registration(in: "JAPANS") == nil)
        #expect(china.registration(in: "B-1234") == "B-1234")
        #expect(china.registration(in: "B-ABCD") == nil)
    }
}

@Suite struct RegistrationReaderTests {
    @Test func findsARegistrationAmongOtherWords() {
        #expect(read("Alaska", "N823AK", "737 MAX") == ["N823AK"])
        #expect(read("operated by G-EUUU today") == ["G-EUUU"])
    }

    @Test func ignoresTextWithNoRegistration() {
        #expect(read("DELTA", "SkyTeam", "NAVY", "UNITED STATES OF AMERICA").isEmpty)
        #expect(read("").isEmpty)
    }

    @Test func readsEveryKindOfDashAsAHyphen() {
        #expect(read("G\u{2013}ABCD") == ["G-ABCD"])
        #expect(read("D\u{2014}AIMA.") == ["D-AIMA"])
    }

    @Test func listsTheSurestReadingFirst() {
        let texts = [
            RecognizedText(text: "N823AK", confidence: 0.4),
            RecognizedText(text: "G-ABCD", confidence: 0.9),
        ]
        let readings = RegistrationReader.readings(in: texts, formats: formats)
        #expect(readings.map(\.registration) == ["G-ABCD", "N823AK"])
        #expect(readings.map(\.country) == ["United Kingdom", "United States"])
    }

    @Test func listsARepeatedRegistrationOnceWithItsBestConfidence() {
        let texts = [
            RecognizedText(text: "N823AK", confidence: 0.4),
            RecognizedText(text: "n823ak", confidence: 0.8),
        ]
        let readings = RegistrationReader.readings(in: texts, formats: formats)
        #expect(readings.count == 1)
        #expect(readings.first?.confidence == 0.8)
    }

    @Test func keepsReadingOrderForEqualConfidence() {
        #expect(read("N1", "N2", "N3") == ["N1", "N2", "N3"])
    }

    @Test func findsNothingWithNoFormats() {
        let texts = [RecognizedText(text: "N823AK", confidence: 0.9)]
        #expect(RegistrationReader.readings(in: texts, formats: []).isEmpty)
    }
}

@Suite struct RegistrationBlockListTests {
    @Test func matchesWhateverTheCaseOrPunctuation() {
        let list = RegistrationBlockList(registrations: ["G-ABCD", "n123ab"])
        #expect(list.contains("G-ABCD"))
        #expect(list.contains("gabcd"))
        #expect(list.contains(" N123AB "))
        #expect(!list.contains("G-ABCE"))
    }

    @Test func anEmptyRegistrationIsNeverBlocked() {
        #expect(!RegistrationBlockList(registrations: [""]).contains(""))
        #expect(!RegistrationBlockList.empty.contains("N123AB"))
    }
}
