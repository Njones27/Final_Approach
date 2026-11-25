import FinalApproachCore
import Foundation
import Testing
import UIKit

@testable import FinalApproach

/// A clock a test can move.
@MainActor
private final class CoordinatorClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

/// A backend a test can make fail or pause, wrapped around the in-memory
/// one. Like the real one, every request to the API first asks for the
/// signed in user's token.
@MainActor
private final class HookedBackend: PhotoBackend {
    /// Whose account the requests reach. A test changes it when another
    /// user signs in, because each user has their own photos.
    var account = "apple-user-1"
    private var accounts: [String: SamplePhotoBackend] = [:]
    /// What the backend holds for the account in use.
    var inner: SamplePhotoBackend { stored(for: account) }

    /// What the backend holds for one account.
    func stored(for account: String) -> SamplePhotoBackend {
        if let existing = accounts[account] { return existing }
        let new = SamplePhotoBackend()
        accounts[account] = new
        return new
    }

    /// Gives the token a request carries. It throws when no one is signed in.
    var accessToken: (() async throws -> String)?
    /// Makes every listing fail with this.
    var listFailure: PhotoBackendError?
    /// Makes every save fail with this.
    var saveFailure: PhotoBackendError?
    var failsPhotoDeletes = false
    /// What the next deletes of the account throw, in order.
    var accountDeleteFailures: [any Error] = []
    /// Runs once, while the next listing is on its way.
    var duringNextListing: (() async -> Void)?
    /// Runs once, after the next image was read and before it is handed over.
    var duringNextImageFetch: (() async -> Void)?
    private(set) var listCount = 0
    private(set) var accountDeleteCount = 0

    private func signedInRequest() async throws {
        _ = try await accessToken?()
    }

    func listPhotos() async throws -> RemoteListing {
        try await signedInRequest()
        listCount += 1
        if let hook = duringNextListing {
            duringNextListing = nil
            await hook()
        }
        if let listFailure { throw listFailure }
        return try await inner.listPhotos()
    }

    func savePhoto(_ photo: SpottedPhoto, image: Data?) async throws -> SavedPhoto {
        try await signedInRequest()
        if let saveFailure { throw saveFailure }
        return try await inner.savePhoto(photo, image: image)
    }

    func fetchImage(from url: URL) async throws -> Data? {
        let image = try await inner.fetchImage(from: url)
        if let hook = duringNextImageFetch {
            duringNextImageFetch = nil
            await hook()
        }
        return image
    }

    func deletePhoto(id: String) async throws {
        try await signedInRequest()
        if failsPhotoDeletes { throw PhotoBackendError.unavailable(status: 503) }
        try await inner.deletePhoto(id: id)
    }

    func deleteAccount() async throws {
        try await signedInRequest()
        accountDeleteCount += 1
        if !accountDeleteFailures.isEmpty {
            throw accountDeleteFailures.removeFirst()
        }
        try await inner.deleteAccount()
    }
}

/// When a sync runs, and how deleting the account reaches the backend.
@MainActor
struct SyncCoordinatorTests {
    private let clock = CoordinatorClock()
    private let identity = SampleIdentityService()
    private let backend = HookedBackend()
    private let sessionStore = MemorySessionStore()
    private let pacing = SyncPacing(delayAfterChange: .seconds(7), accountDeleteAttempts: 3)

    private func appleToken(for userID: String = "apple-user-1") -> String {
        let payload = Data(#"{"sub":"\#(userID)"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    /// A session as the app makes it when it opens, reading the saved sign in.
    private func session() -> AccountSession {
        let clock = self.clock
        identity.now = { clock.now }
        return AccountSession(identity: identity, store: sessionStore, refreshMargin: 120, now: { clock.now })
    }

    /// A coordinator whose wait after a change takes no time.
    private func coordinator(
        _ session: AccountSession,
        hasBackend: Bool = true,
        waits: @escaping (Duration) -> Void = { _ in }
    ) -> SyncCoordinator {
        backend.accessToken = { try await session.accessToken() }
        return SyncCoordinator(
            session: session,
            backend: hasBackend ? backend : nil,
            pacing: pacing,
            sleep: { duration in waits(duration) }
        )
    }

    private func signedIn(as userID: String = "apple-user-1") async throws -> AccountSession {
        let account = session()
        try await account.signIn(identityToken: appleToken(for: userID))
        return account
    }

    private func loggedPhoto(_ id: String = "imported-1") -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: "Boeing 737-800",
            registration: "N8642E",
            airline: "Southwest Airlines",
            activity: "",
            loggedAt: Date(timeIntervalSince1970: 1_800_000_000),
            captureCoordinate: Coordinate(latitude: 33.6220, longitude: -84.3995),
            spotID: "atl-south-approach",
            isLocationUndisclosed: true,
            status: .logged
        )
    }

    private func tinyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    /// The user's own photos on the device, without the samples.
    private func ownPhotoIDs(_ model: CollectionModel) -> [String] {
        model.photos.filter { !$0.isSample }.map { $0.id }.sorted()
    }

    // MARK: When a sync runs

    @Test func nothingIsSentWhileNoOneIsSignedIn() async {
        let sync = coordinator(session())
        let phone = SampleData.model()
        sync.follow(phone)
        phone.add(loggedPhoto())

        await sync.appBecameActive(on: phone)
        await sync.changeSyncFinished()

        #expect(!sync.canSync)
        #expect(backend.listCount == 0)
        #expect(backend.inner.photos.isEmpty)
    }

    @Test func nothingIsSentInABuildWithNoBackend() async throws {
        let account = try await signedIn()
        let sync = coordinator(account, hasBackend: false)
        let phone = SampleData.model()
        phone.add(loggedPhoto())

        await sync.appBecameActive(on: phone)

        #expect(!sync.canSync)
        #expect(backend.listCount == 0)
    }

    @Test func openingTheAppSendsTheUsersPhotos() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())

        await sync.appBecameActive(on: phone)

        #expect(backend.inner.photos["imported-1"] == loggedPhoto())
        #expect(sync.lastReport == SyncReport(uploaded: 1))
        #expect(sync.lastProblem == nil)
        #expect(!sync.isSyncing)
        #expect(phone.syncLedger.owner == "apple-user-1")
    }

    @Test func aChangeIsSentAfterTheWait() async throws {
        var waited: [Duration] = []
        let account = try await signedIn()
        let sync = coordinator(account, waits: { waited.append($0) })
        let phone = SampleData.model()
        sync.follow(phone)

        phone.add(loggedPhoto())
        #expect(backend.inner.photos.isEmpty)
        await sync.changeSyncFinished()

        #expect(waited == [.seconds(7)])
        #expect(backend.inner.photos["imported-1"] == loggedPhoto())
    }

    @Test func severalChangesMadeTogetherGoInOneSync() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        sync.follow(phone)

        phone.add(loggedPhoto("imported-1"))
        phone.add(loggedPhoto("imported-2"))
        phone.updateDetails(
            forPhotoID: "imported-2",
            aircraftType: "Airbus A220-300",
            registration: nil,
            airline: "Delta Air Lines"
        )
        await sync.changeSyncFinished()
        // The waits that were started again have nothing left to do.
        for _ in 0..<20 { await Task.yield() }

        #expect(backend.listCount == 1)
        #expect(backend.inner.photos.keys.sorted() == ["imported-1", "imported-2"])
        #expect(backend.inner.photos["imported-2"]?.aircraftType == "Airbus A220-300")
    }

    @Test func deletingAPhotoIsFollowedByASync() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        await sync.sync(on: phone)
        sync.follow(phone)

        phone.deletePhoto(id: "imported-1")
        await sync.changeSyncFinished()

        #expect(backend.inner.photos.isEmpty)
        #expect(backend.inner.deletedIDs == ["imported-1"])
        #expect(phone.syncLedger.pendingDeletes.isEmpty)
    }

    @Test func aChangeToASamplePhotoStartsNoSync() async throws {
        var waited = 0
        let account = try await signedIn()
        let sync = coordinator(account, waits: { _ in waited += 1 })
        let phone = SampleData.model()
        sync.follow(phone)
        let firstSample = phone.photos.first { $0.isSample }
        let sample = try #require(firstSample)

        phone.deletePhoto(id: sample.id)
        await sync.changeSyncFinished()

        #expect(waited == 0)
        #expect(backend.listCount == 0)
    }

    @Test func aSyncAskedForWhileOneRunsRunsOnceMore() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto("imported-1"))
        backend.duringNextListing = {
            // A photo is logged and a sync is asked for while one runs.
            phone.add(self.loggedPhoto("imported-2"))
            await sync.sync(on: phone)
        }

        await sync.sync(on: phone)

        #expect(backend.listCount == 2)
        #expect(backend.inner.photos.keys.sorted() == ["imported-1", "imported-2"])
        #expect(!sync.isSyncing)
    }

    @Test func aSyncThatCannotStartIsNotRepeatedAtOnce() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        backend.listFailure = .unavailable(status: 503)
        backend.duringNextListing = { await sync.sync(on: phone) }

        await sync.sync(on: phone)

        #expect(backend.listCount == 1)
        #expect(sync.lastProblem == .unavailable)
        #expect(sync.lastReport == nil)

        // It works again the next time the app comes to the front.
        backend.listFailure = nil
        await sync.appBecameActive(on: phone)
        #expect(sync.lastProblem == nil)
        #expect(backend.inner.photos["imported-1"] != nil)
    }

    @Test func onePhotoThatFailsIsReportedAndTheSyncStillCounts() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        backend.saveFailure = .unavailable(status: 503)

        await sync.sync(on: phone)

        #expect(sync.lastReport == SyncReport(failed: 1))
        #expect(sync.lastProblem == nil)
    }

    @Test func aSignInTheBackendEndedStopsTheSyncAndSignsOut() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        identity.endSession(refreshToken: "sample-refresh-1")
        clock.now += 3600

        await sync.sync(on: phone)

        #expect(sync.lastProblem == .signInEnded)
        #expect(account.state == .signedOut)
        #expect(backend.listCount == 0)
        // The photos stay on the device.
        #expect(ownPhotoIDs(phone) == ["imported-1"])
    }

    @Test func anAccountDeletedElsewhereStopsTheSyncAndKeepsThePhotosHere() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        try await backend.inner.deleteAccount()

        await sync.sync(on: phone)

        #expect(sync.lastProblem == .accountDeleted)
        #expect(ownPhotoIDs(phone) == ["imported-1"])
        #expect(account.isSignedIn)
    }

    // MARK: Signing in and out

    @Test func aTestAccountSignsInAndSyncsLikeAnyoneElse() async throws {
        let account = session()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        identity.testAccounts = ["test-one": "long-password"]
        backend.account = "test-one"

        try await sync.signIn(testAccount: "test-one", password: "long-password", on: phone)

        #expect(account.state == .signedIn(userID: "test-one"))
        #expect(account.isTestAccount)
        #expect(backend.inner.photos["imported-1"] == loggedPhoto())
        #expect(sync.status == .upToDate)
    }

    @Test func aTestAccountThatIsRefusedSyncsNothing() async throws {
        let account = session()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        identity.testAccounts = ["test-one": "long-password"]

        await #expect(throws: IdentityError.credentialsRefused) {
            try await sync.signIn(testAccount: "test-one", password: "wrong", on: phone)
        }

        #expect(account.state == .signedOut)
        #expect(backend.listCount == 0)
        #expect(sync.status == .notYet)
    }

    @Test func signingInSendsThePhotosAlreadyOnTheDevice() async throws {
        let account = session()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        #expect(sync.status == .notYet)

        try await sync.signIn(identityToken: appleToken(), on: phone)

        #expect(account.state == .signedIn(userID: "apple-user-1"))
        #expect(backend.inner.photos["imported-1"] == loggedPhoto())
        #expect(sync.status == .upToDate)
    }

    @Test func aSignInAppleOrTheBackendRefusedChangesNothing() async throws {
        let account = session()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        identity.failure = .tokenRefused

        await #expect(throws: IdentityError.tokenRefused) {
            try await sync.signIn(identityToken: appleToken(), on: phone)
        }

        #expect(account.state == .signedOut)
        #expect(backend.listCount == 0)
        #expect(ownPhotoIDs(phone) == ["imported-1"])
    }

    @Test func signingOutKeepsThePhotosAndStopsSending() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        sync.follow(phone)
        phone.add(loggedPhoto("imported-1"))
        await sync.changeSyncFinished()

        await sync.signOut()
        phone.add(loggedPhoto("imported-2"))
        await sync.changeSyncFinished()
        await sync.appBecameActive(on: phone)

        #expect(account.state == .signedOut)
        #expect(ownPhotoIDs(phone) == ["imported-1", "imported-2"])
        #expect(backend.inner.photos.keys.sorted() == ["imported-1"])
        #expect(sync.status == .notYet)
    }

    @Test func theStatusSaysWhereThePhotosStand() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        #expect(sync.status == .notYet)

        var during: SyncStatus?
        backend.duringNextListing = { during = sync.status }
        backend.saveFailure = .unavailable(status: 503)
        await sync.sync(on: phone)
        #expect(during == .syncing)
        #expect(sync.status == .someWaiting)

        backend.saveFailure = nil
        backend.listFailure = .unavailable(status: 503)
        await sync.sync(on: phone)
        #expect(sync.status == .couldNotSync)

        backend.listFailure = nil
        await sync.sync(on: phone)
        #expect(sync.status == .upToDate)

        try await backend.inner.deleteAccount()
        await sync.sync(on: phone)
        #expect(sync.status == .accountDeleted)
    }

    @Test func everyStatusHasWords() {
        let all: [SyncStatus] = [
            .notYet, .syncing, .upToDate, .someWaiting, .couldNotSync, .signInEnded, .accountDeleted,
        ]
        let words = Set(all.map { $0.text })
        #expect(words.count == all.count)
        #expect(!words.contains(""))
    }

    // MARK: Whose photos they are

    @Test func aDeleteOwedToOneUserWaitsForThatUser() async throws {
        let account = try await signedIn(as: "apple-user-1")
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        await sync.sync(on: phone)

        // The delete cannot be confirmed before the user signs out.
        backend.failsPhotoDeletes = true
        phone.deletePhoto(id: "imported-1")
        await sync.sync(on: phone)
        #expect(phone.syncLedger.pendingDeletes == ["imported-1"])
        await account.signOut()
        backend.failsPhotoDeletes = false

        // Another user signs in on the same device. The delete is not theirs.
        try await account.signIn(identityToken: appleToken(for: "apple-user-2"))
        backend.account = "apple-user-2"
        await sync.sync(on: phone)
        #expect(phone.syncLedger.owner == "apple-user-2")
        #expect(phone.syncLedger.pendingDeletes.isEmpty)
        #expect(phone.syncLedger.parkedDeletes == ["apple-user-1": ["imported-1"]])
        #expect(backend.stored(for: "apple-user-2").deletedIDs.isEmpty)
        #expect(backend.stored(for: "apple-user-1").photos["imported-1"] != nil)
        await account.signOut()

        // The first user comes back, and the delete is sent.
        try await account.signIn(identityToken: appleToken(for: "apple-user-1"))
        backend.account = "apple-user-1"
        await sync.sync(on: phone)
        #expect(backend.inner.photos.isEmpty)
        #expect(backend.inner.deletedIDs == ["imported-1"])
        #expect(phone.syncLedger.pendingDeletes.isEmpty)
        #expect(phone.syncLedger.parkedDeletes.isEmpty)
    }

    // MARK: Deleting the account

    @Test func deletingWithNoOneSignedInClearsTheDeviceOnly() async {
        let account = session()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())

        let deleted = await sync.deleteAccountAndPhotos(on: phone)

        #expect(deleted)
        #expect(phone.photos.isEmpty)
        #expect(backend.accountDeleteCount == 0)
        #expect(account.state == .signedOut)
    }

    @Test func deletingTheAccountClearsTheDeviceAndTheBackend() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto(), image: tinyImage())
        await sync.sync(on: phone)
        #expect(backend.inner.images["imported-1"] != nil)

        let deleted = await sync.deleteAccountAndPhotos(on: phone)

        #expect(deleted)
        #expect(phone.photos.isEmpty)
        #expect(phone.syncLedger == SyncLedger())
        #expect(backend.inner.isAccountDeleted)
        #expect(backend.inner.photos.isEmpty)
        #expect(backend.inner.images.isEmpty)
        #expect(account.state == .signedOut)
        #expect(sessionStore.session == nil)
    }

    @Test func aDeleteTheBackendDidNotHearStaysOwedAndIsSentWhenTheAppOpens() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        await sync.sync(on: phone)
        backend.accountDeleteFailures = [URLError(.notConnectedToInternet)]

        let deleted = await sync.deleteAccountAndPhotos(on: phone)

        // The device is cleared at once, and the backend is still owed.
        #expect(deleted)
        #expect(phone.photos.isEmpty)
        #expect(account.state == .deletingAccount(userID: "apple-user-1"))
        #expect(sessionStore.session?.isAccountDeleteOwed == true)
        #expect(backend.inner.photos["imported-1"] != nil)
        #expect(backend.accountDeleteCount == 1)

        // The app is closed and opened again.
        let reopened = session()
        #expect(reopened.state == .deletingAccount(userID: "apple-user-1"))
        let later = coordinator(reopened)
        let listsBefore = backend.listCount
        await later.appBecameActive(on: phone)

        #expect(backend.inner.isAccountDeleted)
        #expect(backend.inner.photos.isEmpty)
        #expect(reopened.state == .signedOut)
        #expect(sessionStore.session == nil)
        // Nothing was fetched back in between.
        #expect(backend.listCount == listsBefore)
        #expect(phone.photos.isEmpty)
    }

    @Test func nothingSyncsWhileADeleteOfTheAccountIsOwed() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        await sync.sync(on: phone)
        backend.accountDeleteFailures = [URLError(.timedOut), URLError(.timedOut)]
        await sync.deleteAccountAndPhotos(on: phone)
        let listsBefore = backend.listCount

        // The user logs a photo before the delete went through.
        sync.follow(phone)
        phone.add(loggedPhoto("imported-2"))
        await sync.changeSyncFinished()
        await sync.sync(on: phone)
        await sync.appBecameActive(on: phone)

        #expect(backend.listCount == listsBefore)
        #expect(backend.inner.photos.keys.sorted() == ["imported-1"])
        #expect(account.state == .deletingAccount(userID: "apple-user-1"))
        // The photo logged since stays on the device.
        #expect(ownPhotoIDs(phone) == ["imported-2"])
    }

    @Test func aBackendThatFailsPartwayIsAskedAgainAtOnce() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        backend.accountDeleteFailures = [
            PhotoBackendError.unavailable(status: 504),
            PhotoBackendError.unavailable(status: 503),
        ]

        await sync.deleteAccountAndPhotos(on: phone)

        #expect(backend.accountDeleteCount == 3)
        #expect(backend.inner.isAccountDeleted)
        #expect(account.state == .signedOut)
    }

    @Test func aBackendThatKeepsFailingIsLeftForTheNextTimeTheAppOpens() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        backend.accountDeleteFailures = Array(repeating: PhotoBackendError.unavailable(status: 503), count: 4)

        await sync.deleteAccountAndPhotos(on: phone)

        #expect(backend.accountDeleteCount == 3)
        #expect(!backend.inner.isAccountDeleted)
        #expect(account.state == .deletingAccount(userID: "apple-user-1"))
    }

    @Test func nothingIsRemovedWhenTheRequestCannotBeSaved() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        phone.add(loggedPhoto())
        sessionStore.failsSaves = true

        let deleted = await sync.deleteAccountAndPhotos(on: phone)

        #expect(!deleted)
        #expect(ownPhotoIDs(phone) == ["imported-1"])
        #expect(backend.accountDeleteCount == 0)
        #expect(account.state == .signedIn(userID: "apple-user-1"))
    }

    @Test func anOwedDeleteIsDoneOnceTheSignInItselfHasEnded() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        let phone = SampleData.model()
        backend.accountDeleteFailures = [URLError(.networkConnectionLost)]
        await sync.deleteAccountAndPhotos(on: phone)
        #expect(account.isAccountDeleteOwed)

        // The first request did reach the backend, which removed the account
        // and with it the sign in.
        identity.endSession(refreshToken: "sample-refresh-1")
        clock.now += 3600
        await sync.appBecameActive(on: phone)

        #expect(!account.isAccountDeleteOwed)
        #expect(account.state == .signedOut)
        #expect(sessionStore.session == nil)
        #expect(backend.accountDeleteCount == 1)
    }

    @Test func aSyncThatWasRunningPutsNothingBackAfterTheAccountIsDeleted() async throws {
        let account = try await signedIn()
        let sync = coordinator(account)
        // Another device sent a photo with its image.
        let tablet = SampleData.model()
        tablet.add(loggedPhoto(), image: tinyImage())
        await sync.sync(on: tablet)
        #expect(backend.inner.images["imported-1"] != nil)

        // The phone is fetching that photo when the user deletes the account.
        let phone = SampleData.model()
        backend.duringNextImageFetch = {
            await sync.deleteAccountAndPhotos(on: phone)
        }
        await sync.sync(on: phone)

        #expect(phone.photos.isEmpty)
        #expect(phone.syncLedger == SyncLedger())
        #expect(backend.inner.isAccountDeleted)
        #expect(account.state == .signedOut)
    }
}

/// What the collection tells the coordinator, and what it remembers.
@MainActor
struct CollectionSyncHookTests {
    private func loggedPhoto(_ id: String = "imported-1") -> SpottedPhoto {
        SpottedPhoto(
            id: id,
            imageName: nil,
            aircraftType: "Boeing 737-800",
            registration: "N8642E",
            airline: "Southwest Airlines",
            activity: "",
            loggedAt: Date(timeIntervalSince1970: 1_800_000_000),
            captureCoordinate: Coordinate(latitude: 33.6220, longitude: -84.3995),
            spotID: "atl-south-approach",
            isLocationUndisclosed: true,
            status: .logged
        )
    }

    @Test func theUsersOwnChangesAreAnnounced() {
        let model = SampleData.model()
        var changes = 0
        model.onLocalChange = { changes += 1 }

        model.add(loggedPhoto())
        #expect(changes == 1)
        model.updateDetails(forPhotoID: "imported-1", aircraftType: "Boeing 737 MAX 8", registration: nil, airline: "")
        #expect(changes == 2)
        model.deletePhoto(id: "imported-1")
        #expect(changes == 3)
    }

    @Test func whatASyncChangesIsNotAnnounced() {
        let model = SampleData.model()
        var changes = 0
        model.onLocalChange = { changes += 1 }

        model.takeRemote(loggedPhoto(), imageData: nil)
        model.updateSyncLedger { $0.noteUploadStarted(id: "imported-1") }
        model.claimSyncLedger(for: "apple-user-1")
        model.removeDeletedElsewhere(id: "imported-1")

        #expect(changes == 0)
    }

    @Test func clearingTheDeviceIsCounted() {
        let model = SampleData.model()
        #expect(model.timesCleared == 0)
        model.deleteAccountAndPhotos()
        model.deleteAccountAndPhotos(alsoOnBackend: true)
        #expect(model.timesCleared == 2)
    }

    @Test func theOwnerOfTheLedgerIsSavedWithTheLibrary() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "final-approach-ledger-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilePhotoStore(directory: directory)

        SampleData.model(store: store).claimSyncLedger(for: "apple-user-1")

        #expect(SampleData.model(store: store).syncLedger.owner == "apple-user-1")
    }

    @Test func clearingOnlyTheDeviceKeepsADeleteTheAccountIsOwed() {
        let model = SampleData.model()
        model.claimSyncLedger(for: "apple-user-1")
        model.add(loggedPhoto())
        model.updateSyncLedger {
            $0.noteUploaded(id: "imported-1", fingerprint: "f1", version: "v1", imageSent: false)
        }
        model.deletePhoto(id: "imported-1")

        model.deleteAccountAndPhotos()

        #expect(model.syncLedger == SyncLedger(parkedDeletes: ["apple-user-1": ["imported-1"]]))
    }
}
