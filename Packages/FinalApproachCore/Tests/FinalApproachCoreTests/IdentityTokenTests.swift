import Foundation
import Testing

@testable import FinalApproachCore

@Suite struct IdentityTokenTests {
    /// A token with the given payload. The header and signature are filler,
    /// because nothing here checks them.
    private func token(payload: String) -> String {
        "eyJhbGciOiJSUzI1NiJ9.\(base64URL(payload)).c2lnbmF0dXJl"
    }

    private func base64URL(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    @Test func readsTheSubject() {
        let token = token(payload: #"{"iss":"https://appleid.apple.com","sub":"001234.abcdef.5678","aud":"com.finalapproach.app"}"#)
        #expect(IdentityToken.subject(of: token) == "001234.abcdef.5678")
    }

    /// Payloads of each length, so every amount of left off padding is read.
    @Test func readsAPayloadOfAnyLength() {
        for subject in ["a", "ab", "abc", "abcd", "abcde"] {
            let token = token(payload: #"{"sub":"\#(subject)"}"#)
            #expect(IdentityToken.subject(of: token) == subject)
        }
    }

    @Test func readsAPayloadThatUsesTheURLSafeLetters() {
        // This payload encodes with both of the letters that differ from
        // plain base64.
        let payload = #"{"sub":"???>>>"}"#
        #expect(base64URL(payload).contains("_"))
        #expect(base64URL(payload).contains("-"))
        #expect(IdentityToken.subject(of: token(payload: payload)) == "???>>>")
    }

    @Test func textThatIsNotATokenHasNoSubject() {
        #expect(IdentityToken.subject(of: "") == nil)
        #expect(IdentityToken.subject(of: "not a token") == nil)
        #expect(IdentityToken.subject(of: "one.two") == nil)
        #expect(IdentityToken.subject(of: "a.b.c.d") == nil)
        #expect(IdentityToken.subject(of: "a.!!!.c") == nil)
        // One letter more than a whole group cannot be base64.
        #expect(IdentityToken.subject(of: "a.abcde.c") == nil)
    }

    @Test func aPayloadThatIsNotAnObjectHasNoSubject() {
        #expect(IdentityToken.subject(of: token(payload: #"["sub"]"#)) == nil)
        #expect(IdentityToken.subject(of: token(payload: "plain text")) == nil)
    }

    @Test func aMissingOrEmptySubjectIsNone() {
        #expect(IdentityToken.subject(of: token(payload: #"{"aud":"com.finalapproach.app"}"#)) == nil)
        #expect(IdentityToken.subject(of: token(payload: #"{"sub":""}"#)) == nil)
        #expect(IdentityToken.subject(of: token(payload: #"{"sub":42}"#)) == nil)
    }
}
