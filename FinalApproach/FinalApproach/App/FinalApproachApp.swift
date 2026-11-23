import SwiftUI

@main
struct FinalApproachApp: App {
    var body: some Scene {
        WindowGroup {
            // The app runs on sample data until the backend exists.
            RootView(model: SampleData.model())
        }
    }
}
