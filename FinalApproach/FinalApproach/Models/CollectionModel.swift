import FinalApproachCore
import Foundation
import Observation
import SwiftUI
import UIKit

/// What went wrong with the photos saved on the device.
enum StorageProblem: Identifiable {
    /// The saved collection could not be read when the app opened.
    case couldNotOpen
    /// A photo or a change could not be written.
    case couldNotSave

    var id: Self { self }

    var title: String {
        switch self {
        case .couldNotOpen: "Your saved photos could not be opened"
        case .couldNotSave: "This change could not be saved"
        }
    }

    var message: String {
        switch self {
        case .couldNotOpen:
            "They are still on this iPhone. Photos you add now will not be saved until the app can open them again."
        case .couldNotSave:
            "It will last until you close the app. Free up some space on this iPhone and try again."
        }
    }
}

/// The state every screen reads. It holds the user's photos, the spots, the
/// vote queue, and the tunable grading values.
///
/// The grading values are passed in so they can come from the backend later
/// without a release.
@Observable
final class CollectionModel {
    private(set) var photos: [SpottedPhoto]
    /// Where logged photos and their images are saved. It is nil in
    /// previews and tests that keep everything in memory.
    @ObservationIgnored private let store: (any PhotoStore)?
    /// The sample photos the user deleted, so they stay deleted.
    @ObservationIgnored private var removedSampleIDs: [String] = []
    /// What the device remembers between syncs with the backend. It is
    /// saved with the library, so a delete the backend has not confirmed
    /// is still owed after the app closes.
    @ObservationIgnored private(set) var syncLedger = SyncLedger()
    /// Where each photo the user posted stands with the vote, by photo id,
    /// as the backend last said. It is kept apart from the photo's own
    /// record, so a new vote never counts as an edit to the photo.
    private(set) var postStandings: [String: PostStanding] = [:]
    /// The fewest votes a grade needs, as the backend last said. It is nil
    /// until the backend has been asked.
    private(set) var backendMinimumVotes: Int?
    /// The spot's page each posted photo is shown on, by photo id, as the
    /// backend last said. A photo that is on no page is left out.
    private(set) var spotShowings: [String: SpotShowing] = [:]
    /// Called after one of the user's own photos leaves the device, or all
    /// of them do. Anything that keeps a copy of a photo clears it then.
    @ObservationIgnored var onPhotosRemoved: (() -> Void)?
    /// Called after the user adds, edits, or deletes one of their own
    /// photos, so a sync can follow. A change a sync makes does not call it.
    @ObservationIgnored var onLocalChange: (() -> Void)?
    /// How many times every photo was removed from the device at once. A
    /// sync that started before the last time must not put anything back.
    @ObservationIgnored private(set) var timesCleared = 0
    /// The images of logged photos that have been shown, by photo id. With
    /// a store this is only a cache, and the saved file is the real copy.
    /// It is not observed, because an image never changes once it is logged.
    @ObservationIgnored private var loadedImages: [String: UIImage] = [:]
    /// Set when the saved collection could not be opened or a change could
    /// not be saved. The Collection screen tells the user and clears it.
    var storageProblem: StorageProblem?
    private(set) var profile: Profile
    private(set) var voteQueue: [VoteCandidate]
    /// How many photos were in today's vote set before any vote.
    let voteSetSize: Int
    /// The listed spots, grouped by airport. A build with a backend takes
    /// them from there, so the list changes with no release.
    private(set) var airports: [Airport]

    let thresholds: TierThresholds
    /// The lowest score at which a check has nothing to suggest. The check
    /// is advice to the photographer, so this never keeps a photo back.
    let passingCheckScore: Double
    /// The values that turn a photo's measurements into check scores.
    let checkRules: CheckRules
    /// The score a check is expected to reach once its fix is made. It sets
    /// how many points of the technical reading a fix is worth.
    let fixTargetScore: Double
    let votingRules: VotingRules
    /// How close, in meters, a photo must be to a spot to count as taken
    /// from it.
    let spotMatchRadius: Double
    /// The longest an aircraft type or an airline may be to go on a spot's
    /// page. The backend refuses a longer one.
    let shownTextMaxLength: Int
    /// How strongly a saved image is compressed, from 0 to 1.
    let storedImageQuality: Double
    /// How each country writes its registrations, used to find one in the
    /// text read off a photo.
    let registrationFormats: [RegistrationFormat]
    /// How the aircraft flying near a photo are ranked.
    let flightRankingRules: FlightRankingRules
    /// The registrations whose identity stays hidden.
    let blockList: RegistrationBlockList
    /// Says what was flying near a photo. It is nil until the backend can
    /// ask the real provider, so a real photo is never matched against
    /// sample aircraft.
    @ObservationIgnored private let flightData: (any FlightDataProvider)?

    /// - Parameters:
    ///   - photos: The sample photos the app ships with.
    ///   - store: Where logged photos are saved. Photos already saved there
    ///     join the collection ahead of the samples.
    init(
        photos: [SpottedPhoto],
        profile: Profile,
        voteQueue: [VoteCandidate],
        airports: [Airport],
        thresholds: TierThresholds,
        passingCheckScore: Double,
        checkRules: CheckRules,
        fixTargetScore: Double,
        votingRules: VotingRules = .launch,
        spotMatchRadius: Double,
        shownTextMaxLength: Int,
        storedImageQuality: Double,
        registrationFormats: [RegistrationFormat],
        flightRankingRules: FlightRankingRules,
        blockList: RegistrationBlockList = .empty,
        flightData: (any FlightDataProvider)? = nil,
        store: (any PhotoStore)? = nil
    ) {
        self.spotMatchRadius = spotMatchRadius
        self.shownTextMaxLength = shownTextMaxLength
        self.storedImageQuality = storedImageQuality
        self.registrationFormats = registrationFormats
        self.flightRankingRules = flightRankingRules
        self.blockList = blockList
        self.flightData = flightData
        var saved = StoredLibrary()
        var usableStore = store
        if let store {
            do {
                saved = try store.loadLibrary()
            } catch {
                // A library that cannot be read is left on the device as it
                // is. Nothing is saved this session, so it is never written
                // over, and the app tells the user.
                usableStore = nil
            }
        }
        self.store = usableStore
        removedSampleIDs = saved.removedSampleIDs
        syncLedger = saved.syncLedger ?? SyncLedger()
        let keptSamples = photos.filter { !saved.removedSampleIDs.contains($0.id) }
        self.photos = saved.photos + keptSamples
        self.profile = profile
        self.voteQueue = voteQueue
        voteSetSize = voteQueue.count
        self.airports = airports
        self.thresholds = thresholds
        self.passingCheckScore = passingCheckScore
        self.checkRules = checkRules
        self.fixTargetScore = fixTargetScore
        self.votingRules = votingRules
        postStandings = saved.postStandings ?? [:]
        backendMinimumVotes = saved.postMinimumVotes
        spotShowings = saved.spotShowings ?? [:]
        if store != nil, usableStore == nil {
            storageProblem = .couldNotOpen
        }
    }

    // MARK: Photos

    func photo(id: String) -> SpottedPhoto? {
        photos.first { $0.id == id }
    }

    /// The checks for a photo, sorted with the weakest first.
    func checkReport(for photo: SpottedPhoto) -> TechnicalCheckReport {
        TechnicalCheckReport(
            results: photo.findings.map(\.result),
            passingScore: passingCheckScore
        )
    }

    /// Scores what was measured in a photo and writes the feedback. A check
    /// that could not be measured is left out. The fixes come weakest check
    /// first, which is also the largest gain first.
    func technicalCheck(
        for measurements: PhotoMeasurements,
        camera: CameraSettings?
    ) -> (findings: [CheckFinding], fixes: [SuggestedFix]) {
        let outcomes = TechnicalCheckEngine.outcomes(
            for: measurements,
            rules: checkRules,
            passingScore: passingCheckScore,
            camera: camera
        )
        let report = TechnicalCheckReport(
            results: outcomes.map(\.result),
            passingScore: passingCheckScore
        )
        let findings = outcomes.map { CheckFinding(result: $0.result, detail: $0.detail) }
        let fixes = report.needsWork.compactMap { result -> SuggestedFix? in
            guard let advice = outcomes.first(where: { $0.result.kind == result.kind })?.advice else {
                return nil
            }
            // A fix is worth its gain in the technical reading. It is not
            // worth points of the grade, which the votes alone set.
            let gain = report.overallGain(raising: result.kind, to: fixTargetScore)
            return SuggestedFix(
                kind: result.kind,
                title: advice.title,
                detail: advice.detail,
                points: max(1, Int(gain.rounded()))
            )
        }
        return (findings, fixes)
    }

    /// The technical reading, or nil when the check has not run. It is
    /// advice for the photographer. No other user sees it, and it takes no
    /// part in the grade.
    func technicalScore(for photo: SpottedPhoto) -> Double? {
        checkReport(for: photo).overallScore()
    }

    /// The fewest votes a photo needs before its grade can be final. The
    /// backend's word wins, so it can change with no release.
    var minimumVotes: Int {
        backendMinimumVotes ?? votingRules.minimumVotes
    }

    /// Where a photo is on its way to a grade.
    ///
    /// A photo the user posted takes this from what the backend last said
    /// about its post. A sample photo takes it from its own status.
    func progress(for photo: SpottedPhoto, at now: Date = Date()) -> PhotoProgress {
        if !photo.isSample, let standing = postStandings[photo.id] {
            if let score = standing.finalScore {
                return .graded(score: Double(score), voteCount: standing.voteCount)
            }
            return .voting(
                votesIn: standing.voteCount,
                votesNeeded: standing.votesNeeded(minimumVotes: minimumVotes),
                hoursLeft: standing.hoursLeft(at: now)
            )
        }
        switch photo.status {
        case .logged:
            return .logged
        case let .voting(votesIn, hoursLeft):
            return .voting(
                votesIn: votesIn,
                votesNeeded: max(minimumVotes - votesIn, 0),
                hoursLeft: hoursLeft
            )
        case let .graded(voteAverage, voteCount):
            // The tier is set from the rounded grade, so the number on
            // screen and the tier beside it always agree.
            guard let score = FinalGrade.score(voteAverage: voteAverage, rules: votingRules)?.rounded() else {
                return .logged
            }
            return .graded(score: score, voteCount: voteCount)
        }
    }

    /// The final grade as a whole number, or nil until voting has closed.
    /// The votes alone set it, so a photo is never marked down for style.
    func finalScore(for photo: SpottedPhoto) -> Double? {
        guard case let .graded(score, _) = progress(for: photo) else { return nil }
        return score
    }

    /// True for a photo the user logged that has not been posted yet.
    func canBePosted(_ photo: SpottedPhoto) -> Bool {
        !photo.isSample && progress(for: photo) == .logged
    }

    /// The technical reading as a whole number, for a photo that has no
    /// grade yet. The owner's collection shows it as a private stand-in
    /// until the votes are in. It is nil once the photo is graded.
    func provisionalScore(for photo: SpottedPhoto) -> Double? {
        guard finalScore(for: photo) == nil else { return nil }
        return technicalScore(for: photo)?.rounded()
    }

    /// The tier a photo holds. A photo with no final grade is `logged`.
    func tier(for photo: SpottedPhoto) -> Tier {
        guard let score = finalScore(for: photo) else { return .logged }
        return thresholds.tier(forScore: score)
    }

    /// The user's best graded photo, which leads the collection.
    var bestPhoto: SpottedPhoto? {
        var best: (photo: SpottedPhoto, score: Double)?
        for photo in photos {
            guard let score = finalScore(for: photo) else { continue }
            if let current = best, current.score >= score { continue }
            best = (photo, score)
        }
        return best?.photo
    }

    /// The image to show for a photo. A sample photo comes from the asset
    /// catalog and a logged one from the file saved on the device.
    func image(for photo: SpottedPhoto) -> Image {
        if let name = photo.imageName {
            return Image(name)
        }
        if let logged = loggedImage(forPhotoID: photo.id) {
            return Image(uiImage: logged)
        }
        return Image(systemName: "photo")
    }

    /// The image of a logged photo, read from the device the first time it
    /// is asked for.
    private func loggedImage(forPhotoID id: String) -> UIImage? {
        if let loaded = loadedImages[id] {
            return loaded
        }
        guard let data = store?.imageData(forPhotoID: id), let image = UIImage(data: data) else {
            return nil
        }
        loadedImages[id] = image
        return image
    }

    /// Adds a photo to the front of the collection and saves it on the
    /// device. Pass the image for a photo imported from the library.
    func add(_ photo: SpottedPhoto, image: UIImage? = nil) {
        defer { noteLocalChange(to: photo) }
        if let image {
            loadedImages[photo.id] = image
        }
        photos.insert(photo, at: 0)
        guard let store else { return }
        do {
            if let image, let data = image.jpegData(compressionQuality: storedImageQuality) {
                try store.saveImage(Self.withoutMetadata(data), forPhotoID: photo.id)
            }
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    /// Changes the aircraft details of a photo the user logged, and saves
    /// the change. Passing nil for the registration leaves it as it is.
    func updateDetails(forPhotoID id: String, aircraftType: String, registration: String?, airline: String) {
        guard let index = photos.firstIndex(where: { $0.id == id }), !photos[index].isSample else { return }
        defer { onLocalChange?() }
        let newRegistration = registration?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        photos[index] = photos[index].replacingDetails(
            aircraftType: aircraftType.trimmingCharacters(in: .whitespacesAndNewlines),
            registration: newRegistration,
            // A blocked registration is kept with the photo and never shown.
            isRegistrationBlocked: newRegistration.map { isBlocked(registration: $0) },
            airline: airline.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard let store else { return }
        do {
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    /// Removes a photo and its saved image from the device. A photo the
    /// backend may hold is noted as a pending delete, and the next sync
    /// removes that copy too.
    func deletePhoto(id: String) {
        guard let photo = photo(id: id) else { return }
        defer { noteLocalChange(to: photo) }
        photos.removeAll { $0.id == id }
        loadedImages[id] = nil
        if photo.isSample {
            if !removedSampleIDs.contains(id) {
                removedSampleIDs.append(id)
            }
        } else {
            syncLedger.noteDeletedHere(id: id)
            // Deleting the photo takes its post down with it, and takes
            // it off its spot's page.
            postStandings[id] = nil
            spotShowings[id] = nil
            onPhotosRemoved?()
        }
        guard let store else { return }
        do {
            try store.deleteImage(forPhotoID: id)
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    /// Removes every photo and every saved image from the device.
    ///
    /// Pass true for `alsoOnBackend` when the account itself is being
    /// deleted, which removes the backend's copies with it, so nothing is
    /// left for a sync to remember. With false only this device is cleared,
    /// and a delete the backend has not confirmed yet is still owed to the
    /// account it was made in.
    func deleteAccountAndPhotos(alsoOnBackend: Bool = false) {
        for photo in photos where photo.isSample && !removedSampleIDs.contains(photo.id) {
            removedSampleIDs.append(photo.id)
        }
        photos.removeAll()
        loadedImages.removeAll()
        postStandings.removeAll()
        spotShowings.removeAll()
        onPhotosRemoved?()
        syncLedger.noteDeviceCleared(accountDeleted: alsoOnBackend)
        timesCleared += 1
        guard let store else { return }
        do {
            try store.deleteEverything()
            // The list of deleted samples is written back, so they do not
            // return the next time the app opens.
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    /// Tells whoever follows the collection that the user changed one of
    /// their own photos. A sample photo is never sent, so it is left out.
    private func noteLocalChange(to photo: SpottedPhoto) {
        guard !photo.isSample else { return }
        onLocalChange?()
    }

    /// True when a logged photo still has an image, in memory or saved on
    /// the device.
    func hasStoredImage(forPhotoID id: String) -> Bool {
        loadedImages[id] != nil || store?.imageData(forPhotoID: id) != nil
    }

    /// Writes the logged photos and the deleted samples to the device. The
    /// samples themselves ship with the app and are never written.
    private func saveLibrary(to store: any PhotoStore) throws {
        try store.saveLibrary(
            StoredLibrary(
                photos: photos.filter { !$0.isSample },
                removedSampleIDs: removedSampleIDs,
                syncLedger: syncLedger,
                postStandings: postStandings.isEmpty ? nil : postStandings,
                postMinimumVotes: backendMinimumVotes,
                spotShowings: spotShowings.isEmpty ? nil : spotShowings
            )
        )
    }

    // MARK: Sync

    /// The user's own photos as a sync sees them. Sample photos ship with
    /// the app and are left out.
    func localSyncStates() -> [LocalPhotoState] {
        photos.compactMap { photo in
            guard !photo.isSample, let fingerprint = try? photo.syncFingerprint() else { return nil }
            return LocalPhotoState(
                id: photo.id,
                fingerprint: fingerprint,
                hasImage: hasStoredImage(forPhotoID: photo.id)
            )
        }
    }

    /// The image of a logged photo as it is sent to the backend. Any
    /// metadata is taken out on the way, so the image never says where it
    /// was taken, whatever wrote the saved file.
    func storedImageData(forPhotoID id: String) -> Data? {
        let saved = store?.imageData(forPhotoID: id)
            ?? loadedImages[id]?.jpegData(compressionQuality: storedImageQuality)
        return saved.map(Self.withoutMetadata)
    }

    /// The image file with its Exif, XMP, and IPTC blocks removed. Bytes
    /// that are not a JPEG come back as they were, and the backend refuses
    /// them if they are posted.
    static func withoutMetadata(_ data: Data) -> Data {
        JPEGMetadata.removed(from: data) ?? data
    }

    /// Takes the backend's copy of a photo, from another device or after an
    /// edit made there, and saves it. Pass the image when it was fetched.
    func takeRemote(_ photo: SpottedPhoto, imageData: Data?) {
        guard !photo.isSample else { return }
        let image = imageData.flatMap(UIImage.init(data:))
        if let image {
            loadedImages[photo.id] = image
        }
        if let index = photos.firstIndex(where: { $0.id == photo.id }) {
            photos[index] = photo
        } else {
            // The collection runs newest first, with the samples last.
            let index = photos.firstIndex { $0.isSample || $0.loggedAt < photo.loggedAt } ?? photos.endIndex
            photos.insert(photo, at: index)
        }
        guard let store else { return }
        do {
            if image != nil, let imageData {
                try store.saveImage(imageData, forPhotoID: photo.id)
            }
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    /// Saves the image of a photo the device already holds. Data that is
    /// not an image is refused.
    @discardableResult
    func takeRemoteImage(_ data: Data, forPhotoID id: String) -> Bool {
        guard let photo = photo(id: id), !photo.isSample, let image = UIImage(data: data) else { return false }
        loadedImages[id] = image
        guard let store else { return true }
        do {
            try store.saveImage(data, forPhotoID: id)
        } catch {
            storageProblem = .couldNotSave
        }
        return true
    }

    /// Removes a photo that was deleted on another device, with its image.
    /// The backend already knows, so nothing is left owing.
    func removeDeletedElsewhere(id: String) {
        syncLedger.noteDeleteSettled(id: id)
        guard let photo = photo(id: id), !photo.isSample else {
            saveSyncLedger()
            return
        }
        photos.removeAll { $0.id == id }
        loadedImages[id] = nil
        postStandings[id] = nil
        spotShowings[id] = nil
        onPhotosRemoved?()
        guard let store else { return }
        do {
            try store.deleteImage(forPhotoID: id)
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    // MARK: Posting

    /// Takes the backend's word on every post the user has made, and saves
    /// it. A photo the backend lists no post for is not posted.
    func takePostListing(_ listing: PostListing) {
        let own = Set(photos.filter { !$0.isSample }.map(\.id))
        let standings = listing.standings.filter { own.contains($0.key) }
        // A listing that names no usable minimum leaves the last one.
        let minimum = listing.minimumVotes.flatMap { $0 > 0 ? $0 : nil } ?? backendMinimumVotes
        // Only a posted photo can be on a spot's page.
        let showings = listing.showings.filter { standings[$0.key] != nil }
        guard standings != postStandings || minimum != backendMinimumVotes || showings != spotShowings else {
            return
        }
        postStandings = standings
        backendMinimumVotes = minimum
        spotShowings = showings
        savePostStandings()
    }

    /// Takes where one photo stands, right after it was posted.
    func takePostStanding(_ standing: PostStanding, forPhotoID id: String) {
        guard let photo = photo(id: id), !photo.isSample else { return }
        postStandings[id] = standing
        savePostStandings()
    }

    /// Takes the spot's page a posted photo is now shown on, or nil once it
    /// is on none.
    func takeSpotShowing(_ showing: SpotShowing?, forPhotoID id: String) {
        guard postStandings[id] != nil || showing == nil, spotShowings[id] != showing else { return }
        spotShowings[id] = showing
        savePostStandings()
    }

    private func savePostStandings() {
        guard let store else { return }
        do {
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    /// Makes the sync ledger the signed in user's before a sync runs for
    /// them. A ledger that belongs to another account is started again, and
    /// the deletes that account is still owed are set aside for it.
    func claimSyncLedger(for userID: String) {
        guard syncLedger.owner != userID else { return }
        updateSyncLedger { $0.claim(for: userID) }
    }

    /// Changes what the device remembers between syncs, and saves it.
    func updateSyncLedger(_ change: (inout SyncLedger) -> Void) {
        change(&syncLedger)
        saveSyncLedger()
    }

    private func saveSyncLedger() {
        guard let store else { return }
        do {
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    // MARK: Identification

    /// Works out which aircraft is in a picked photo, from the text read
    /// off it and from what was flying there. The user confirms or
    /// corrects the result.
    ///
    /// - Parameter place: Where the photo was taken, from the file or from
    ///   the spot the user tagged. Flight data needs a place and a capture
    ///   time, so without both only the text is used.
    func identification(for photo: ImportedPhoto, at place: Coordinate?) async -> Identification {
        let readings = RegistrationReader.readings(in: photo.recognizedText, formats: registrationFormats)
        var flights: [RankedFlight] = []
        if let flightData, let place, let time = photo.metadata.capturedAt {
            // A lookup that fails leaves the user to type the details.
            let sightings = (try? await flightData.flights(near: place, at: time)) ?? []
            flights = FlightRanker.rank(
                sightings,
                seenFrom: place,
                facing: photo.metadata.heading,
                rules: flightRankingRules
            )
        }
        return AircraftIdentifier.identify(readings: readings, flights: flights, blockList: blockList)
    }

    /// True when a registration must stay hidden, such as one on the FAA
    /// LADD list.
    func isBlocked(registration: String) -> Bool {
        blockList.contains(registration)
    }

    // MARK: Collection slots

    /// The slots of one collection view, in name order. Each slot keeps the
    /// user's best shot of one type, airline, or registration.
    func slots(_ kind: SlotKind) -> [CollectionEntry] {
        // A photo with no grade is ranked by its technical reading, so the
        // slots work before anyone has voted. A grade always outranks one.
        let shots = photos.map {
            $0.slotShot(score: finalScore(for: $0), technicalReading: technicalScore(for: $0)?.rounded())
        }
        return CollectionBook.entries(for: shots, kind: kind, thresholds: thresholds)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// One slot, or nil when no photo fills it any more.
    func slot(_ kind: SlotKind, key: String) -> CollectionEntry? {
        slots(kind).first { $0.key == key }
    }

    /// The photos in a slot, best first.
    func photos(in entry: CollectionEntry) -> [SpottedPhoto] {
        entry.photoIDs.compactMap { photo(id: $0) }
    }

    // MARK: Profile

    var typesCollected: Int {
        slots(.aircraftType).count
    }

    var photosGraded: Int {
        photos.filter { finalScore(for: $0) != nil }.count
    }

    // MARK: Voting

    /// The photo waiting for a vote, or nil when today's set is finished.
    var currentVoteCandidate: VoteCandidate? {
        voteQueue.first
    }

    /// The position of the current photo in today's set, starting at 1.
    var votePosition: Int {
        voteSetSize - voteQueue.count + 1
    }

    /// Records a vote for the current photo and moves to the next one. A
    /// vote outside the scale is ignored.
    func castVote(_ vote: Int) {
        guard votingRules.isValid(vote: vote), !voteQueue.isEmpty else { return }
        voteQueue.removeFirst()
        profile.votesCast += 1
    }

    /// Moves to the next photo without voting.
    func skipVote() {
        guard !voteQueue.isEmpty else { return }
        voteQueue.removeFirst()
    }

    // MARK: Spots

    func spot(id: String) -> Spot? {
        for airport in airports {
            if let spot = airport.spots.first(where: { $0.id == id }) {
                return spot
            }
        }
        return nil
    }

    /// Takes the backend's list of spots. It replaces the list in hand.
    func takeSpotCatalog(_ airports: [Airport]) {
        guard airports != self.airports else { return }
        self.airports = airports
    }

    /// The listed spot a photo was taken from, as its owner sees it. It is
    /// the spot the photo was logged with while that spot is still listed,
    /// and otherwise the listed spot nearest to where it was taken.
    ///
    /// It reads the photo's own location, so nothing shown to another
    /// person may use it. Those use `spotShowing(for:)`.
    func listedSpot(for photo: SpottedPhoto) -> Spot? {
        if let id = photo.spotID, let logged = spot(id: id) {
            return logged
        }
        return photo.ownerCaptureCoordinate.flatMap { nearestSpot(to: $0) }
    }

    /// The aircraft type and airline other people may read beside a photo
    /// on a spot's page.
    ///
    /// A blocked aircraft shows neither, because either one can help name
    /// it. A line the backend would refuse is left out.
    func shownDetails(for photo: SpottedPhoto) -> (aircraftType: String?, airline: String?) {
        guard !photo.hasBlockedRegistration else { return (nil, nil) }
        return (
            ShownText.line(from: photo.aircraftType, maxLength: shownTextMaxLength),
            ShownText.line(from: photo.airline, maxLength: shownTextMaxLength)
        )
    }

    /// The spot's page a photo may be shown on, with what is read beside
    /// it there. It is nil for a sample photo, for a photo whose owner kept
    /// the location private, and for one taken away from every listed spot.
    func spotShowing(for photo: SpottedPhoto) -> SpotShowing? {
        guard !photo.isSample, !photo.isLocationUndisclosed else { return nil }
        // Only what the owner disclosed is read here.
        let listed = photo.publicSpotID.flatMap { spot(id: $0) }
            ?? photo.publicCaptureCoordinate.flatMap { nearestSpot(to: $0) }
        guard let listed else { return nil }
        let details = shownDetails(for: photo)
        return SpotShowing(spotID: listed.id, aircraftType: details.aircraftType, airline: details.airline)
    }

    /// The photos logged with no aircraft type, newest first. They fill no
    /// type slot, so the types view lists them by themselves.
    var unidentifiedPhotos: [SpottedPhoto] {
        photos
            .filter { !$0.isTypeKnown }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    /// The listed spot closest to where a photo was taken, or nil when none
    /// is within `spotMatchRadius`.
    func nearestSpot(to coordinate: Coordinate) -> Spot? {
        let landmarks = airports.flatMap(\.spots).compactMap { spot in
            spot.coordinate.map { Landmark(id: spot.id, point: $0) }
        }
        let found = NearestLandmark.find(to: coordinate, among: landmarks, within: spotMatchRadius)
        return found.flatMap { spot(id: $0.landmark.id) }
    }

    /// The user's own photos that carry a location, newest first. The owner
    /// sees every one of them on the map, shared or not.
    var locatedPhotos: [SpottedPhoto] {
        photos
            .filter(\.hasCaptureLocation)
            .sorted { $0.loggedAt > $1.loggedAt }
    }
}
