import SwiftUI

@main
struct FinalApproachApp: App {
    /// The app runs on sample data until the backend supplies the rest.
    /// Photos the user logs are saved on the device.
    private let model: CollectionModel
    /// Syncs the user's photos with the backend once someone is signed in.
    /// A build with no backend never signs in, so it never syncs.
    private let sync: SyncCoordinator

    init() {
        let model = SampleData.model(store: FilePhotoStore.standard)
        let sync = SyncCoordinator.forThisBuild()
        sync.follow(model)
        self.model = model
        self.sync = sync
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, sync: sync)
        }
    }
}
