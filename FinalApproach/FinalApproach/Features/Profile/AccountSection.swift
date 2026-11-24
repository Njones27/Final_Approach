import AuthenticationServices
import SwiftUI

/// The part of Profile that signs the user in and out, and says where their
/// photos stand with the backend. It is shown only in a build that has a
/// backend.
struct AccountSection: View {
    @Environment(CollectionModel.self) private var model
    @Environment(SyncCoordinator.self) private var sync
    @State private var isSigningIn = false
    @State private var didSignInFail = false

    var body: some View {
        Section {
            switch sync.session.state {
            case .signedOut:
                AppleSignInButton { result in finishSignIn(result) }
                    .frame(height: 50)
                    .listRowInsets(EdgeInsets())
                    .disabled(isSigningIn)
                    .alert("Signing in did not work", isPresented: $didSignInFail) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Nothing changed. Try again in a moment.")
                    }
            case .signedIn:
                LabeledContent("Signed in", value: "With Apple")
                LabeledContent("Photos", value: sync.status.text)
                Button("Sign out") {
                    Task { await sync.signOut() }
                }
            case .deletingAccount:
                Text("Your account is being deleted.")
                    .foregroundStyle(Theme.ink)
                Button("Try again now") {
                    Task { await sync.sendAccountDeleteIfOwed() }
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        switch sync.session.state {
        case .signedOut:
            "Sign in to keep your photos with your account and bring them to another iPhone."
        case .signedIn:
            "Signing out leaves your photos on this iPhone."
        case .deletingAccount:
            "It finishes the next time this iPhone is online."
        }
    }

    /// Takes Apple's answer. The identity token in it is what the backend
    /// checks, so nothing else from the answer is kept.
    private func finishSignIn(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8)
            else {
                didSignInFail = true
                return
            }
            isSigningIn = true
            Task {
                defer { isSigningIn = false }
                do {
                    try await sync.signIn(identityToken: token, on: model)
                } catch {
                    #if DEBUG
                    print("AccountSection: Signing in failed. \(error)")
                    #endif
                    didSignInFail = true
                }
            }
        case .failure(let error):
            // Closing Apple's sheet is not a failure.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            #if DEBUG
            print("AccountSection: Apple gave no sign in. \(error)")
            #endif
            didSignInFail = true
        }
    }
}

#Preview("Signed out") {
    List { AccountSection() }
        .environment(SampleData.model())
        .environment(SyncCoordinator.preview(.signedOut))
}

#Preview("Signed in") {
    List { AccountSection() }
        .environment(SampleData.model())
        .environment(SyncCoordinator.preview(.signedIn))
}

#Preview("Deleting the account") {
    List { AccountSection() }
        .environment(SampleData.model())
        .environment(SyncCoordinator.preview(.deletingAccount))
}
