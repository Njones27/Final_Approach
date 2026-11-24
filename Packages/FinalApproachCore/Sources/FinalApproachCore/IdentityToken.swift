import Foundation

/// Reads what a signed identity token says, without checking it.
///
/// The backend checks the token from Sign in with Apple. The app only needs
/// the user's id from it, to know which user to sign in as. Nothing here
/// may be used to decide that a token is real.
public enum IdentityToken {
    /// The user the token names, or nil when the text is not a token.
    public static func subject(of token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let payload = data(fromBase64URL: String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: payload),
              let claims = object as? [String: Any],
              let subject = claims["sub"] as? String,
              !subject.isEmpty
        else { return nil }
        return subject
    }

    /// The bytes behind text in the URL safe form of base64, which leaves
    /// the padding off.
    static func data(fromBase64URL text: String) -> Data? {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let extra = base64.count % 4
        guard extra != 1 else { return nil }
        if extra > 0 {
            base64 += String(repeating: "=", count: 4 - extra)
        }
        return Data(base64Encoded: base64)
    }
}
