import SwiftUI

@main
struct FinalApproachApp: App {
    /// The app runs on sample data until the backend supplies the rest.
    /// Photos the user logs are saved on the device.
    private let model: CollectionModel
    /// Syncs the user's photos with the backend once someone is signed in.
    /// A build with no backend never signs in, so it never syncs.
    private let sync: SyncCoordinator
    /// Takes votes on photos other people posted. A build with no backend
    /// keeps the sample set on the Vote screen.
    private let voting: VotingModel
    /// Lists the spots and the photos shown at each. A build with no
    /// backend keeps the sample spots.
    private let spots: SpotsModel

    init() {
        // A build with a backend takes its spots from there. The sample
        // spots are made up, so such a build starts with none.
        let hasBackend = AppEnvironment.apiBaseURL != nil
        let model = SampleData.model(store: FilePhotoStore.standard, airports: hasBackend ? [] : nil)
        let sync = SyncCoordinator.forThisBuild()
        sync.follow(model)
        let spots = SpotsModel.forThisBuild(session: sync.session)
        spots.follow(model)
        self.model = model
        self.sync = sync
        self.spots = spots
        voting = VotingModel.forThisBuild(session: sync.session)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, sync: sync, voting: voting, spots: spots)
        }
    }
}
