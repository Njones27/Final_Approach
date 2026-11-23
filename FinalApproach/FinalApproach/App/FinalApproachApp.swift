import SwiftUI

@main
struct FinalApproachApp: App {
    var body: some Scene {
        WindowGroup {
            // The app runs on sample data until the backend exists. Photos
            // the user logs are saved on the device.
            RootView(model: SampleData.model(store: FilePhotoStore.standard))
        }
    }
}
