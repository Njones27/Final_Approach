import AuthenticationServices
import SwiftUI

/// Apple's own sign in button.
///
/// Apple draws it in black or in white and takes no color from the app, so
/// this is the one view that reads the appearance to pick between them. It
/// asks for no name and no email, because the app needs neither.
struct AppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Called with Apple's answer, or with the reason there is none.
    let onCompletion: (Result<ASAuthorization, any Error>) -> Void

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            onCompletion(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        // The button keeps the style it was made with, so a change of
        // appearance makes a new one.
        .id(colorScheme)
    }
}

#Preview {
    AppleSignInButton { _ in }
        .frame(height: 50)
        .padding()
        .background(Theme.ground)
}
