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
    let airports: [Airport]

    let thresholds: TierThresholds
    /// The lowest technical check score that counts as passed.
    let passingCheckScore: Double
    /// The values that turn a photo's measurements into check scores.
    let checkRules: CheckRules
    /// The score a check is expected to reach once its fix is made. It sets
    /// how many points a fix is worth.
    let fixTargetScore: Double
    let gradeWeights: GradeWeights
    let votingRules: VotingRules
    /// How close, in meters, a photo must be to a spot to count as taken
    /// from it.
    let spotMatchRadius: Double
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
        gradeWeights: GradeWeights = .launch,
        votingRules: VotingRules = .launch,
        spotMatchRadius: Double,
        storedImageQuality: Double,
        registrationFormats: [RegistrationFormat],
        flightRankingRules: FlightRankingRules,
        blockList: RegistrationBlockList = .empty,
        flightData: (any FlightDataProvider)? = nil,
        store: (any PhotoStore)? = nil
    ) {
        self.spotMatchRadius = spotMatchRadius
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
        self.gradeWeights = gradeWeights
        self.votingRules = votingRules
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
            // The technical check is only part of the grade, so a fix is
            // worth its gain in the check times that share.
            let gain = report.overallGain(raising: result.kind, to: fixTargetScore) * gradeWeights.ai
            return SuggestedFix(
                kind: result.kind,
                title: advice.title,
                detail: advice.detail,
                points: max(1, Int(gain.rounded()))
            )
        }
        return (findings, fixes)
    }

    /// The technical check score, or nil when the check has not run.
    func technicalScore(for photo: SpottedPhoto) -> Double? {
        checkReport(for: photo).overallScore()
    }

    /// The final grade as a whole number, or nil until voting has closed.
    func finalScore(for photo: SpottedPhoto) -> Double? {
        guard case let .graded(voteAverage, _) = photo.status,
              let technical = technicalScore(for: photo)
        else { return nil }
        // The tier is set from the rounded grade, so the number on screen and
        // the tier beside it always agree.
        return FinalGrade.score(
            aiScore: technical,
            voteAverage: voteAverage,
            weights: gradeWeights,
            rules: votingRules
        )?.rounded()
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
        if let image {
            loadedImages[photo.id] = image
        }
        photos.insert(photo, at: 0)
        guard let store else { return }
        do {
            if let image, let data = image.jpegData(compressionQuality: storedImageQuality) {
                try store.saveImage(data, forPhotoID: photo.id)
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
        photos.removeAll { $0.id == id }
        loadedImages[id] = nil
        if photo.isSample {
            if !removedSampleIDs.contains(id) {
                removedSampleIDs.append(id)
            }
        } else {
            syncLedger.noteDeletedHere(id: id)
        }
        guard let store else { return }
        do {
            try store.deleteImage(forPhotoID: id)
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
    }

    /// Removes the account's photos and every saved image from the device.
    /// The backend's copies go with the account itself, which the caller
    /// deletes through `PhotoBackend.deleteAccount`, so nothing is left for
    /// a sync to remember.
    func deleteAccountAndPhotos() {
        for photo in photos where photo.isSample && !removedSampleIDs.contains(photo.id) {
            removedSampleIDs.append(photo.id)
        }
        photos.removeAll()
        loadedImages.removeAll()
        syncLedger = SyncLedger()
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
                syncLedger: syncLedger
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

    /// The image of a logged photo as it is sent to the backend. It is the
    /// saved file, which carries no metadata and so no location.
    func storedImageData(forPhotoID id: String) -> Data? {
        if let saved = store?.imageData(forPhotoID: id) {
            return saved
        }
        return loadedImages[id]?.jpegData(compressionQuality: storedImageQuality)
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
        guard let store else { return }
        do {
            try store.deleteImage(forPhotoID: id)
            try saveLibrary(to: store)
        } catch {
            storageProblem = .couldNotSave
        }
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
        let shots = photos.map { $0.slotShot(score: finalScore(for: $0)) }
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
