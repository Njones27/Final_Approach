import SwiftUI

/// The four top-level sections, in the order the tab bar shows them.
private enum AppTab: Int, Hashable {
    case collection
    case spots
    case vote
    case profile
}

/// The four top-level sections. Adding a photo is an action, so it is a
/// button on the Collection screen and not a tab.
struct RootView: View {
    @State private var model: CollectionModel
    @State private var sync: SyncCoordinator
    @State private var voting: VotingModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system
    @State private var selectedTab = AppTab.collection
    /// How each tab last arrived, so its content can come in from the side
    /// of the tab the user left.
    @State private var arrivals: [AppTab: TabArrival] = [:]
    @State private var tabChanges = 0

    init(model: CollectionModel, sync: SyncCoordinator, voting: VotingModel) {
        _model = State(initialValue: model)
        _sync = State(initialValue: sync)
        _voting = State(initialValue: voting)
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Collection", systemImage: "square.grid.2x2", value: AppTab.collection) {
                CollectionView()
                    .environment(\.tabArrival, arrival(for: .collection))
            }
            Tab("Spots", systemImage: "mappin.and.ellipse", value: AppTab.spots) {
                SpotsView()
                    .environment(\.tabArrival, arrival(for: .spots))
            }
            Tab("Vote", systemImage: "star", value: AppTab.vote) {
                VoteView()
                    .environment(\.tabArrival, arrival(for: .vote))
            }
            Tab("Profile", systemImage: "person", value: AppTab.profile) {
                ProfileView()
                    .environment(\.tabArrival, arrival(for: .profile))
            }
        }
        .tint(Theme.ink)
        .environment(model)
        .environment(sync)
        .environment(voting)
        .preferredColorScheme(appearance.colorScheme)
        // The photos are brought into line with the backend each time the
        // app opens or comes back to the front.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await sync.appBecameActive(on: model) }
        }
    }

    /// The selected tab. A change also records which side the new tab sits
    /// on, in the same update, so its content knows where to come in from.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selectedTab
        } set: { tab in
            guard tab != selectedTab else { return }
            tabChanges += 1
            arrivals[tab] = TabArrival(
                visit: tabChanges,
                side: tab.rawValue > selectedTab.rawValue ? 1 : -1
            )
            selectedTab = tab
        }
    }

    private func arrival(for tab: AppTab) -> TabArrival {
        arrivals[tab] ?? TabArrival()
    }
}

#Preview {
    let sync = SyncCoordinator.preview()
    RootView(model: SampleData.model(), sync: sync, voting: .preview(session: sync.session))
}
