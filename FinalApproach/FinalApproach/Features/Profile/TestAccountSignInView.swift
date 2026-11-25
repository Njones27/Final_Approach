import SwiftUI

/// Signs in a test account with its name and password.
///
/// Nobody can sign up for a test account. The owner makes each one by hand,
/// so this sheet only signs in. It is for trying the app with a second
/// account, and for App Review.
struct TestAccountSignInView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var problem: String?
    @FocusState private var focus: Field?

    private enum Field {
        case name, password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                } footer: {
                    Text(problem ?? "A test account is made by the app's owner. You cannot make one here.")
                        .foregroundStyle(Theme.secondaryText)
                }
                Section {
                    Button {
                        signIn()
                    } label: {
                        if isSigningIn {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign in")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!Self.canSend(name: name, password: password) || isSigningIn)
                }
            }
            .navigationTitle("Test account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focus = .name }
            .interactiveDismissDisabled(isSigningIn)
        }
    }

    private func signIn() {
        guard Self.canSend(name: name, password: password), !isSigningIn else { return }
        isSigningIn = true
        problem = nil
        Task {
            defer { isSigningIn = false }
            do {
                try await sync.signIn(testAccount: name, password: password, on: model)
                dismiss()
            } catch {
                #if DEBUG
                print("TestAccountSignInView: Signing in failed. \(error)")
                #endif
                // A password that did not work is not kept on screen.
                password = ""
                problem = Self.message(for: error)
            }
        }
    }

    /// True when there is a name and a password to send.
    static func canSend(name: String, password: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    /// What to tell the user when a sign in did not work.
    static func message(for error: any Error) -> String {
        switch error as? IdentityError {
        case .credentialsRefused?:
            "That name and password did not match a test account."
        case .testAccountNotReady?:
            "This test account is not ready yet. Its password has to be set for good first."
        case .unavailable?:
            "The backend could not be reached. Try again in a moment."
        case .refused(status: _, name: "InvalidParameterException")?:
            // The pool says this when sign in by password is turned off.
            "This backend does not take test accounts."
        default:
            "Signing in did not work. Try again in a moment."
        }
    }
}

#Preview {
    TestAccountSignInView()
        .environment(SampleData.model())
        .environment(SyncCoordinator.preview(.signedOut))
}
