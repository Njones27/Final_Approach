import FinalApproachCore
import PhotosUI
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
    @State private var isPickingPhoto = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var importedPhoto: ImportedPhoto?
    @State private var isImporting = false
    @State private var importFailed = false

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
                        isPickingPhoto = true
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
            .photosPicker(
                isPresented: $isPickingPhoto,
                selection: $pickedItem,
                matching: .images,
                // Ask for the file as it is, so its saved metadata survives.
                preferredItemEncoding: .current
            )
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                pickedItem = nil
                Task {
                    await importPhoto(from: item)
                }
            }
            .sheet(item: $importedPhoto) { photo in
                AddPhotoView(photo: photo)
            }
            .alert("This photo could not be read", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Pick another photo or try again.")
            }
            .overlay {
                if isImporting {
                    ProgressView("Reading your photo")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
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
                isPickingPhoto = true
            }
        }
        .padding(.top, 80)
    }

    /// Loads the picked file, reads its image and metadata, and measures it
    /// for the technical check. The photo is not added to the collection
    /// until the user logs it.
    private func importPhoto(from item: PhotosPickerItem) async {
        isImporting = true
        defer { isImporting = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              var photo = PhotoMetadataReader.importPhoto(from: data)
        else {
            importFailed = true
            return
        }
        // The technical check measures the photo now, so its feedback is
        // ready the moment the photo is logged.
        photo.measurements = await PhotoAnalyzer.measurements(for: photo.image, rules: model.checkRules)
        importedPhoto = photo
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
