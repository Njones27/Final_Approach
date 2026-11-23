import SwiftUI

/// Placeholder profile screen. It shows which environment the build targets
/// so a beta build is never mistaken for a production one.
struct ProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Build") {
                    LabeledContent("Environment", value: AppEnvironment.current.displayName)
                    LabeledContent("Backend", value: AppEnvironment.apiHost ?? "Not configured")
                }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}
