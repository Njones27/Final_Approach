import FinalApproachCore
import SwiftUI

/// Where a tap on a photo leads.
enum PhotoRoute: Hashable {
    case photo(String)
    case technicalCheck(String)
}

/// How the collection grid is ordered.
enum CollectionOrder: String, CaseIterable, Identifiable {
    case aircraftType
    case airline
    case grade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aircraftType: "By type"
        case .airline: "By airline"
        case .grade: "By grade"
        }
    }
}

/// The user's photos as a photo-first grid. The best graded photo leads at
/// full width and the rest follow in two columns.
struct CollectionView: View {
    @Environment(CollectionModel.self) private var model
    @State private var order = CollectionOrder.aircraftType
    @State private var isAddingPhoto = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if model.photos.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .background(Theme.ground)
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(order.title) {
                        Picker("Order", selection: $order) {
                            ForEach(CollectionOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add a photo", systemImage: "plus") {
                        isAddingPhoto = true
                    }
                }
            }
            .navigationDestination(for: PhotoRoute.self) { route in
                switch route {
                case let .photo(id):
                    PhotoDetailView(photoID: id)
                case let .technicalCheck(id):
                    TechnicalCheckView(photoID: id)
                }
            }
            .sheet(isPresented: $isAddingPhoto) {
                AddPhotoView()
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 2) {
            if let hero = model.bestPhoto {
                NavigationLink(value: PhotoRoute.photo(hero.id)) {
                    CollectionTile(photo: hero, isHero: true)
                }
                .buttonStyle(TilePressStyle())
            }
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(remainingPhotos) { photo in
                    NavigationLink(value: PhotoRoute.photo(photo.id)) {
                        CollectionTile(photo: photo, isHero: false)
                    }
                    .buttonStyle(TilePressStyle())
                }
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No photos yet", systemImage: "airplane")
        } description: {
            Text("Add your first photo to start your collection.")
        } actions: {
            Button("Add a photo") {
                isAddingPhoto = true
            }
        }
        .padding(.top, 80)
    }

    /// Every photo except the one that leads, in the chosen order.
    private var remainingPhotos: [SpottedPhoto] {
        let heroID = model.bestPhoto?.id
        let rest = model.photos.filter { $0.id != heroID }
        switch order {
        case .aircraftType:
            return rest.sorted {
                $0.aircraftType.localizedStandardCompare($1.aircraftType) == .orderedAscending
            }
        case .airline:
            return rest.sorted {
                $0.airline.localizedStandardCompare($1.airline) == .orderedAscending
            }
        case .grade:
            // Graded photos come first, best first. Ungraded ones follow.
            return rest.sorted {
                (model.finalScore(for: $0) ?? -1) > (model.finalScore(for: $1) ?? -1)
            }
        }
    }
}

/// Dims and shrinks a tile a little while it is pressed.
private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

#Preview {
    CollectionView()
        .environment(SampleData.model())
}

#Preview("Empty") {
    let model = SampleData.model()
    model.deleteAccountAndPhotos()
    return CollectionView()
        .environment(model)
}
