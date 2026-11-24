import SwiftUI

/// The photographer's totals, level, and settings.
struct ProfileView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(SyncCoordinator.self) private var sync
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system
    @AppStorage(LocationPrivacySetting.storageKey) private var locationPrivacy = LocationPrivacySetting.askEachTime
    @State private var isConfirmingDelete = false
    @State private var didDeleteFail = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("Settings") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { setting in
                            Text(setting.displayName).tag(setting)
                        }
                    }
                    Picker("Location privacy", selection: $locationPrivacy) {
                        ForEach(LocationPrivacySetting.allCases) { setting in
                            Text(setting.displayName).tag(setting)
                        }
                    }
                }

                // Signing in needs a backend, so a build with none leaves
                // the section out.
                if sync.session.canSignIn {
                    AccountSection()
                }

                // Shows which backend this build targets, so a beta build is
                // never mistaken for a production one.
                Section("Build") {
                    LabeledContent("Environment", value: AppEnvironment.current.displayName)
                    LabeledContent("Backend", value: AppEnvironment.apiHost ?? "Not configured")
                }

                Section {
                    Button("Delete account and photos", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .arrivesWithTab()
            .background(Theme.ground)
            .navigationTitle("Profile")
            .confirmationDialog(
                "Delete your account and photos?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete account and photos", role: .destructive) {
                    Task {
                        // The coordinator also deletes the account on the
                        // backend when someone is signed in.
                        let deleted = await sync.deleteAccountAndPhotos(on: model)
                        didDeleteFail = !deleted
                    }
                }
            } message: {
                Text("Every photo and grade is removed. This cannot be undone.")
            }
            .alert("Your account could not be deleted", isPresented: $didDeleteFail) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing was removed. Try again in a moment.")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.profile.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Text("Spotting since \(model.profile.memberSince)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            HStack(alignment: .top, spacing: 0) {
                StatView(value: model.typesCollected, label: "Types collected")
                StatView(value: model.photosGraded, label: "Photos graded")
                StatView(value: model.profile.votesCast, label: "Votes cast")
            }

            level

            Text("Your votes count \(model.profile.voteWeight.formatted(.number.precision(.fractionLength(1)))) times because they often match the final grade.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var level: some View {
        let profile = model.profile
        let progress = profile.experienceForNextLevel > 0
            ? Double(profile.experience) / Double(profile.experienceForNextLevel) * 100
            : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Level \(profile.level)")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(profile.experienceToNextLevel) XP to level \(profile.level + 1)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            ScoreMeter(score: progress, tint: Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Level \(profile.level). \(profile.experience) of \(profile.experienceForNextLevel) XP."
        )
    }
}

/// One total with its label, such as 42 over "Votes cast".
private struct StatView: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.condensed(34, relativeTo: .title))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProfileView()
        .environment(SampleData.model())
        .environment(SyncCoordinator.preview(.signedOut))
}
