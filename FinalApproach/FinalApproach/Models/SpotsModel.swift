import Foundation
import Observation
import UIKit

/// Runs the Spots screen against the backend. It asks for the list of spots
/// and hands it to the collection, and it holds the graded photos shown at
/// each spot.
///
/// The photos here are other people's. All this holds about one is its
/// image, its grade, and the aircraft type and airline its owner chose to
/// show, so the screen has no name, registration, or position to show.
@Observable
final class SpotsModel {
    /// Where the list of spots stands.
    enum Phase: Equatable {
        /// Nothing has been asked for yet.
        case idle
        case loading
        case loaded
        case signInNeeded
        /// The backend could not be reached, and no list is in hand.
        case couldNotLoad
    }

    /// The photos shown at one spot, as far as they are known.
    struct Page: Equatable {
        enum Phase: Equatable {
            case loading
            case loaded
            /// The backend could not be reached. Photos loaded before stay.
            case couldNotLoad
        }

        var phase: Phase
        /// The photos, best first.
        var photos: [SpotPhoto] = []
    }

    private(set) var phase: Phase = .idle
    /// The page of each spot that has been asked for, by spot id.
    private(set) var pages: [String: Page] = [:]

    let session: AccountSession

    @ObservationIgnored private let backend: any SpotBackend
    /// True when the backend answers a signed in user only. The sample
    /// spots of a build with no backend need no one signed in.
    @ObservationIgnored private let needsSignIn: Bool
    /// The longest side, in pixels, of the copy of a photo kept for the
    /// screen.
    @ObservationIgnored private let thumbnailSide: CGFloat
    /// The copies of photos made for the screen, by post id. They live in
    /// memory only, and the system may drop them when memory runs short.
    @ObservationIgnored private let thumbnails = NSCache<NSString, UIImage>()
    /// The request for the list of spots that is running, when one is.
    /// The model owns it, so a screen that goes away does not cut it off.
    @ObservationIgnored private var listLoad: Task<Void, Never>?
    /// The request for each spot's photos that is running, by spot id.
    @ObservationIgnored private var pageLoads: [String: Task<Void, Never>] = [:]
    /// How many times in a row the list is asked for again because the
    /// sign in changed while it was on its way.
    @ObservationIgnored private let listAttempts: Int

    init(
        session: AccountSession,
        backend: any SpotBackend,
        needsSignIn: Bool,
        thumbnailSide: CGFloat = 1200,
        listAttempts: Int = 3
    ) {
        self.session = session
        self.backend = backend
        self.needsSignIn = needsSignIn
        self.thumbnailSide = thumbnailSide
        self.listAttempts = listAttempts
    }

    /// True when the spots cannot be asked for because no one is signed in.
    private var isSignedOut: Bool { needsSignIn && !session.isSignedIn }

    private var signedInUserID: String? {
        if case let .signedIn(userID) = session.state { userID } else { nil }
    }

    /// Clears the copies of photos kept here whenever the user deletes a
    /// photo or their account. One of them may be the user's own photo, as
    /// a spot's page shows it.
    func follow(_ model: CollectionModel) {
        model.onPhotosRemoved = { [weak self] in
            self?.forgetPhotos()
        }
    }

    /// Call when the app opens, when the Spots screen appears, and when
    /// the sign in changes. It asks for the list of spots and hands it to
    /// the collection, which uses it to say which spot a photo was taken
    /// from.
    ///
    /// A list that could not be fetched leaves the one in hand. A call
    /// made while the list is on its way waits for that answer.
    func refresh(on model: CollectionModel) async {
        if let listLoad {
            await listLoad.value
            return
        }
        let load = Task { await self.loadList(on: model) }
        listLoad = load
        await load.value
        listLoad = nil
    }

    private func loadList(on model: CollectionModel) async {
        // The list is asked for again when the user signs out or changes
        // while it is on its way.
        for _ in 0..<max(1, listAttempts) {
            guard !isSignedOut else {
                forgetPhotos()
                phase = .signInNeeded
                return
            }
            let userID = signedInUserID
            let hadList = phase == .loaded
            if !hadList {
                phase = .loading
            }
            var result = Phase.loaded
            var airports: [Airport]?
            do {
                airports = try await backend.airports()
            } catch PhotoBackendError.notSignedIn, PhotoBackendError.accountDeleted {
                result = .signInNeeded
            } catch {
                #if DEBUG
                print("SpotsModel: The spots could not be loaded. \(error)")
                #endif
                result = hadList ? .loaded : .couldNotLoad
            }
            guard signedInUserID == userID, !isSignedOut else { continue }
            if let airports {
                model.takeSpotCatalog(airports)
            }
            if result == .signInNeeded {
                forgetPhotos()
            }
            phase = result
            return
        }
        if phase == .loading {
            phase = .couldNotLoad
        }
    }

    /// Asks for the photos shown at one spot. Call it each time the spot is
    /// put on the screen, because a link to an image works for a few
    /// minutes only. The photos loaded before stay until the new ones
    /// arrive. A call made while they are on their way waits for them.
    func loadPhotos(atSpotID spotID: String) async {
        guard !isSignedOut else { return }
        if let running = pageLoads[spotID] {
            await running.value
            return
        }
        let load = Task { await self.fetchPhotos(atSpotID: spotID) }
        pageLoads[spotID] = load
        await load.value
        pageLoads[spotID] = nil
    }

    private func fetchPhotos(atSpotID spotID: String) async {
        if pages[spotID] == nil {
            pages[spotID] = Page(phase: .loading)
        }
        var loaded: [SpotPhoto]?
        do {
            loaded = try await backend.photos(atSpotID: spotID)
        } catch {
            #if DEBUG
            print("SpotsModel: The photos at a spot could not be loaded. \(error)")
            #endif
        }

        guard !isSignedOut else { return }
        let before = pages[spotID]?.photos ?? []
        guard let loaded else {
            pages[spotID] = Page(phase: .couldNotLoad, photos: before)
            return
        }
        // A photo that left the page was taken off or deleted, so the copy
        // made for the screen goes too.
        let stillShown = Set(loaded.map(\.id))
        for photo in before where !stillShown.contains(photo.id) {
            thumbnails.removeObject(forKey: photo.id as NSString)
        }
        pages[spotID] = Page(phase: .loaded, photos: loaded)
    }

    /// The image of one photo on a spot's page, made small enough for the
    /// screen. It is nil when the link ran out or the image is gone.
    ///
    /// The full image is never kept. A page can hold many photos, and a
    /// small copy of each is all the screen draws.
    func thumbnail(for photo: SpotPhoto) async -> UIImage? {
        let key = photo.id as NSString
        if let kept = thumbnails.object(forKey: key) {
            return kept
        }
        guard let data = try? await backend.image(from: photo.imageURL), let image = UIImage(data: data) else {
            return nil
        }
        let size = Self.fitted(image.size, within: thumbnailSide)
        // The small copy is made off the main thread, so the screen does
        // not stall while a page fills.
        let small = await image.byPreparingThumbnail(ofSize: size) ?? image
        // A copy is kept only while its photo is still on a page. The
        // photos may have been cleared while this ran.
        if isShown(photoID: photo.id) {
            thumbnails.setObject(small, forKey: key)
        }
        return small
    }

    /// Drops every photo held here, with the copies made for the screen.
    /// The spots themselves stay.
    func forgetPhotos() {
        if !pages.isEmpty {
            pages = [:]
        }
        thumbnails.removeAllObjects()
    }

    /// True while a copy of this photo is kept for the screen.
    func hasThumbnail(forPhotoID id: String) -> Bool {
        thumbnails.object(forKey: id as NSString) != nil
    }

    private func isShown(photoID: String) -> Bool {
        pages.values.contains { page in
            page.photos.contains { $0.id == photoID }
        }
    }

    /// The size an image is drawn at so its longest side is no more than
    /// `side`. An image that is already small keeps its size.
    static func fitted(_ size: CGSize, within side: CGFloat) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > side, side > 0 else { return size }
        let scale = side / longest
        return CGSize(
            width: max((size.width * scale).rounded(), 1),
            height: max((size.height * scale).rounded(), 1)
        )
    }
}

extension SpotsModel {
    /// The spots model the app uses, made from this build's settings. A
    /// build with no backend gets the sample spots, which are made up.
    static func forThisBuild(session: AccountSession) -> SpotsModel {
        guard let apiURL = AppEnvironment.apiBaseURL else {
            return SpotsModel(session: session, backend: SampleData.spotBackend(), needsSignIn: false)
        }
        return SpotsModel(
            session: session,
            backend: HTTPSpotBackend(
                baseURL: apiURL,
                transport: URLSessionTransport.standard,
                accessToken: { try await session.accessToken() }
            ),
            needsSignIn: true
        )
    }

    /// A spots model on sample services, for previews. Nothing it does
    /// leaves the device.
    ///
    /// Pass no backend for the sample spots and their photos.
    static func preview(
        session: AccountSession,
        backend: SampleSpotBackend? = nil,
        needsSignIn: Bool = false
    ) -> SpotsModel {
        SpotsModel(session: session, backend: backend ?? SampleData.spotBackend(), needsSignIn: needsSignIn)
    }
}
