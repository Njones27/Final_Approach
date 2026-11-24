import FinalApproachCore
import PhotosUI
import SwiftUI

/// The collection views. Three of them sort the photos into slots, where
/// each slot keeps the best shot of one type, airline, or registration.
enum CollectionGrouping: String, CaseIterable, Identifiable {
    case aircraftType
    case airline
    case registration
    case allPhotos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aircraftType: "Types"
        case .airline: "Airlines"
        case .registration: "Registrations"
        case .allPhotos: "All photos"
        }
    }

    /// The kind of slot this view shows, or nil for the view of every
    /// photo.
    var slotKind: SlotKind? {
        switch self {
        case .aircraftType: .aircraftType
        case .airline: .airline
        case .registration: .registration
        case .allPhotos: nil
        }
    }

    /// What to say when no photo fills a slot in this view.
    var emptyText: String {
        switch self {
        case .aircraftType: "No types yet."
        case .airline: "No airlines yet. Add the airline when you log a photo."
        case .registration: "No registrations yet. Add the registration when you log a photo."
        case .allPhotos: "No photos yet."
        }
    }
}

/// The user's collection as a photo-first grid. The best graded photo leads
/// at full width. Under it the grid shows one tile for each slot, or one for
/// each photo.
struct CollectionView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ties each tile to the photo screen it opens, so the photo grows out
    /// of its tile and shrinks back into it.
    @Namespace private var photoZoom
    @State private var grouping = CollectionGrouping.aircraftType
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
            .arrivesWithTab()
            .background(Theme.ground)
            .navigationTitle("Collection")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(grouping.title) {
                        Picker("View", selection: $grouping) {
                            ForEach(CollectionGrouping.allCases) { grouping in
                                Text(grouping.title).tag(grouping)
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
            .photoDestinations(zoomingIn: photoZoom)
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
            .alert(
                model.storageProblem?.title ?? "",
                isPresented: isShowingStorageProblem,
                presenting: model.storageProblem
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { problem in
                Text(problem.message)
            }
            .overlay {
                ZStack {
                    if isImporting {
                        ProgressView("Reading your photo")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .transition(importNoticeTransition)
                    }
                }
                .animation(Motion.press, value: isImporting)
            }
            // A photo that joins the collection is confirmed with a tap.
            .sensoryFeedback(trigger: model.photos.count) { old, new in
                new > old ? .success : nil
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 2) {
            if let hero = model.bestPhoto {
                photoTile(for: hero, isHero: true, source: .hero(hero.id))
            }
            if let kind = grouping.slotKind {
                let slots = model.slots(kind)
                // A photo with no type fills no type slot. The types view
                // still shows each one, so a logged photo is never hidden.
                let unidentified = kind == .aircraftType
                    ? model.unidentifiedPhotos.filter { $0.id != model.bestPhoto?.id }
                    : []
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(slots) { slot in
                        slotTile(for: slot)
                    }
                    ForEach(unidentified) { photo in
                        photoTile(for: photo, isHero: false, source: .tile(photo.id))
                    }
                }
                if slots.isEmpty, unidentified.isEmpty {
                    Text(grouping.emptyText)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(remainingPhotos) { photo in
                        photoTile(for: photo, isHero: false, source: .tile(photo.id))
                    }
                }
            }
        }
        .padding(.top, 8)
        // Tiles slide to their new places when the view changes or a photo
        // joins or leaves.
        .animation(reduceMotion ? nil : Motion.swap, value: grouping)
        .animation(reduceMotion ? nil : Motion.swap, value: model.photos.map(\.id))
    }

    /// A tile for one photo. It opens the photo, which grows out of it.
    private func photoTile(for photo: SpottedPhoto, isHero: Bool, source: ZoomSource) -> some View {
        NavigationLink(value: PhotoRoute.photo(id: photo.id, source: source)) {
            CollectionTile(photo: photo, isHero: isHero)
                .matchedTransitionSource(id: source, in: photoZoom)
        }
        .buttonStyle(TilePressStyle())
    }

    /// A tile for one slot, showing its best shot. A slot with one shot
    /// opens that photo. A slot with more opens its own screen.
    @ViewBuilder
    private func slotTile(for slot: CollectionEntry) -> some View {
        if let best = model.photo(id: slot.bestPhotoID) {
            let source = ZoomSource.tile(slot.id)
            let route = slot.photoIDs.count > 1
                ? PhotoRoute.slot(kind: slot.kind, key: slot.key)
                : PhotoRoute.photo(id: best.id, source: source)
            NavigationLink(value: route) {
                CollectionTile(photo: best, isHero: false, title: slot.title, shotCount: slot.photoIDs.count)
                    .matchedTransitionSource(id: source, in: photoZoom)
            }
            .buttonStyle(TilePressStyle())
        }
    }

    /// Shows the alert while the model reports a storage problem, and
    /// clears the problem when the alert closes.
    private var isShowingStorageProblem: Binding<Bool> {
        Binding(
            get: { model.storageProblem != nil },
            set: { isShowing in
                if !isShowing {
                    model.storageProblem = nil
                }
            }
        )
    }

    /// The import notice fades in and grows a little. With Reduce Motion on
    /// it only fades.
    private var importNoticeTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.96))
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
        // The text is read now too, so a registration on the aircraft is
        // already filled in when the Add screen opens.
        photo.recognizedText = await RegistrationTextReader.recognizedText(in: photo.image)
        importedPhoto = photo
    }

    /// Every photo except the one that leads, newest first.
    private var remainingPhotos: [SpottedPhoto] {
        let heroID = model.bestPhoto?.id
        return model.photos
            .filter { $0.id != heroID }
            .sorted { $0.loggedAt > $1.loggedAt }
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
