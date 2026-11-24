import Testing

@testable import FinalApproachCore

struct ShownTextTests {
    @Test func aLineIsTrimmed() {
        #expect(ShownText.line(from: "  Boeing 737-800\n", maxLength: 80) == "Boeing 737-800")
    }

    @Test func anEmptyLineIsLeftOut() {
        #expect(ShownText.line(from: "", maxLength: 80) == nil)
        #expect(ShownText.line(from: "   \n ", maxLength: 80) == nil)
    }

    @Test func aLineThatIsTooLongIsLeftOut() {
        let longest = String(repeating: "a", count: 80)

        #expect(ShownText.line(from: longest, maxLength: 80) == longest)
        #expect(ShownText.line(from: longest + "a", maxLength: 80) == nil)
    }

    @Test func theLengthIsCountedAsTheBackendCountsIt() {
        // An emoji is one character here and two units to the backend.
        let planes = String(repeating: "✈️", count: 3)

        #expect(planes.count == 3)
        #expect(ShownText.line(from: planes, maxLength: 5) == nil)
        #expect(ShownText.line(from: planes, maxLength: 6) == planes)
    }

    @Test func aLineWithAControlCharacterIsLeftOut() {
        #expect(ShownText.line(from: "Delta\u{0007}Air Lines", maxLength: 80) == nil)
        #expect(ShownText.line(from: "Delta\tAir Lines", maxLength: 80) == nil)
        #expect(ShownText.line(from: "Delta\u{007F}", maxLength: 80) == nil)
    }
}
