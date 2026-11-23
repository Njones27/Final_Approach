import SwiftUI

/// The five top-level tabs. Each tab is a placeholder until the UI pass
/// replaces it with a designed screen.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Collection", systemImage: "square.grid.2x2") {
                CollectionView()
            }
            Tab("Map", systemImage: "map") {
                PlaceholderScreen(
                    title: "Map",
                    systemImage: "map",
                    message: "Spotting locations will appear here."
                )
            }
            Tab("Add", systemImage: "plus.circle") {
                PlaceholderScreen(
                    title: "Add",
                    systemImage: "camera",
                    message: "Capture or import a photo to log an aircraft."
                )
            }
            Tab("Vote", systemImage: "star") {
                PlaceholderScreen(
                    title: "Vote",
                    systemImage: "star",
                    message: "Photos waiting for your vote will appear here."
                )
            }
            Tab("Profile", systemImage: "person.crop.circle") {
                ProfileView()
            }
        }
    }
}

#Preview {
    RootView()
}
