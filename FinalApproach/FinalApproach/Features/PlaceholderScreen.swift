import SwiftUI

/// A stand-in for a screen that has not been designed yet.
struct PlaceholderScreen: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
                .navigationTitle(title)
        }
    }
}

#Preview {
    PlaceholderScreen(title: "Map", systemImage: "map", message: "Spotting locations will appear here.")
}
