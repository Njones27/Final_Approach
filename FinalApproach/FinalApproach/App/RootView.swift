import SwiftUI

/// The four top-level sections. Adding a photo is an action, so it is a
/// button on the Collection screen and not a tab.
struct RootView: View {
    @State private var model: CollectionModel
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system

    init(model: CollectionModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        TabView {
            Tab("Collection", systemImage: "square.grid.2x2") {
                CollectionView()
            }
            Tab("Spots", systemImage: "mappin.and.ellipse") {
                SpotsView()
            }
            Tab("Vote", systemImage: "star") {
                VoteView()
            }
            Tab("Profile", systemImage: "person") {
                ProfileView()
            }
        }
        .tint(Theme.ink)
        .environment(model)
        .preferredColorScheme(appearance.colorScheme)
    }
}

#Preview {
    RootView(model: SampleData.model())
}
