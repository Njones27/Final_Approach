import Foundation
import Observation

/// How sync is paced. The values are passed in so they can be tuned, and so
/// a test does not wait.
struct SyncPacing: Equatable {
    /// How long a sync waits after the user changes a photo. Several changes
    /// made together then go in one sync.
    var delayAfterChange: Duration = .seconds(2)
    /// How many times in a row a delete of the account is sent while the
    /// backend fails, before it waits for the next time the app opens. A
    /// very large account can need more than one request.
    var accountDeleteAttempts = 3
}

/// Why the last sync stopped before it could do anything.
enum SyncProblem: Equatable {
    /// The sign in no longer works.
    case signInEnded
    /// The backend says this account was deleted.
    case accountDeleted
    /// The backend could not be reached, or it failed.
    case unavailable
}

/// What the Profile screen says about the user's photos and the backend.
enum SyncStatus: Equatable {
    case notYet
    case syncing
    case upToDate
    /// Some photos could not be sent or fetched and are tried again.
    case someWaiting
    case couldNotSync
    case signInEnded
    case accountDeleted

    var text: String {
        switch self {
        case .notYet: "Not synced yet"
        case .syncing: "Syncing"
        case .upToDate: "Up to date"
        case .someWaiting: "Some photos are waiting"
        case .couldNotSync: "Could not sync"
        case .signInEnded: "Sign in again"
        case .accountDeleted: "This account was deleted"
        }
    }
}

/// What came of asking to post a photo for votes.
enum PostOutcome: Equatable {
    case posted
    /// No one is signed in, or the sign in no longer works.
    case signInNeeded
    /// The photo or its image has not reached the backend, most likely
    /// because the device is offline.
    case notSavedYet
    /// The image has a location written inside it, so the backend will not
    /// show it to other users.
    case imageHasLocation
    /// The photo is gone, or was posted already.
    case photoGone
    case couldNotPost
}

/// What came of asking to put a photo on a spot's page, or to take it off.
enum SpotShowOutcome: Equatable {
    case done
    /// No one is signed in, or the sign in no longer works.
    case signInNeeded
    /// The photo is not posted, is gone, or its owner kept the location
    /// private.
    case cannotShow
    /// The photo was taken away from every listed spot, or its spot is no
    /// longer listed.
    case spotNotListed
    case couldNotChange
}

/// Decides when a sync runs, posts a photo for votes, shows a posted photo
/// at its spot, and carries a delete of the account through to the backend.
///
/// A sync runs when the app comes to the front and shortly after the user
/// changes a photo. Nothing runs while no one is signed in, so a build with
/// no backend never makes a request.
@Observable
final class SyncCoordinator {
    let session: AccountSession

    private(set) var isSyncing = false
    /// What the last sync that ran to its end did.
    private(set) var lastReport: SyncReport?
    /// Why the last sync stopped, or nil when it ran to its end.
    private(set) var lastProblem: SyncProblem?

    @ObservationIgnored private let backend: (any PhotoBackend)?
    @ObservationIgnored private let engine: SyncEngine?
    @ObservationIgnored private let posts: (any PostBackend)?
    /// Callers waiting for the sync that is running to finish.
    @ObservationIgnored private var syncWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let pacing: SyncPacing
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    /// The wait before the sync that follows a change.
    @ObservationIgnored private var waiting: Task<Void, Never>?
    /// Set when a sync is asked for while one runs, so it runs once more.
    @ObservationIgnored private var isAskedAgain = false
    @ObservationIgnored private var isSendingAccountDelete = false

    /// Pass no backend for a build that has none. Such a build never syncs.
    /// Pass no `posts` and posting is not offered.
    init(
        session: AccountSession,
        backend: (any PhotoBackend)?,
        posts: (any PostBackend)? = nil,
        pacing: SyncPacing,
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.session = session
        self.backend = backend
        self.engine = backend.map { SyncEngine(backend: $0) }
        // A photo is synced before it is posted, so posting needs both.
        self.posts = backend == nil ? nil : posts
        self.pacing = pacing
        self.sleep = sleep
    }

    /// True when a sync could run now.
    var canSync: Bool { engine != nil && session.isSignedIn }

    /// True in a build whose backend takes posts. A build without one shows
    /// no way to post.
    var offersPosting: Bool { posts != nil }

    /// Where the user's photos stand with the backend, for the Profile
    /// screen.
    var status: SyncStatus {
        if isSyncing { return .syncing }
        switch lastProblem {
        case .signInEnded?: return .signInEnded
        case .accountDeleted?: return .accountDeleted
        case .unavailable?: return .couldNotSync
        case nil: break
        }
        guard let lastReport else { return .notYet }
        return lastReport.isClean ? .upToDate : .someWaiting
    }

    // MARK: Signing in and out

    /// Signs in with the identity token from Sign in with Apple, and then
    /// syncs. The photos already on the device are sent to the account.
    func signIn(identityToken: String, on model: CollectionModel) async throws {
        try await session.signIn(identityToken: identityToken)
        lastReport = nil
        lastProblem = nil
        await sync(on: model)
    }

    /// Signs in a test account, and then syncs, as a sign in with Apple does.
    func signIn(testAccount name: String, password: String, on model: CollectionModel) async throws {
        try await session.signIn(testAccount: name, password: password)
        lastReport = nil
        lastProblem = nil
        await sync(on: model)
    }

    /// Signs out. The photos stay on the device, and nothing more is sent.
    func signOut() async {
        waiting?.cancel()
        await session.signOut()
        lastReport = nil
        lastProblem = nil
    }

    // MARK: When a sync runs

    /// Starts a sync shortly after each change the user makes to the
    /// collection.
    func follow(_ model: CollectionModel) {
        model.onLocalChange = { [weak self, weak model] in
            guard let self, let model else { return }
            self.noteChange(on: model)
        }
    }

    /// Call when the app opens or comes back to the front. A delete of the
    /// account that is still owed goes first.
    func appBecameActive(on model: CollectionModel) async {
        await sendAccountDeleteIfOwed()
        await sync(on: model)
    }

    /// Call after the user adds, edits, or deletes a photo. The sync starts
    /// after a short wait, and a newer change starts the wait again.
    func noteChange(on model: CollectionModel) {
        guard canSync else { return }
        waiting?.cancel()
        waiting = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(self.pacing.delayAfterChange)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.sync(on: model)
        }
    }

    /// Waits for the sync that follows the last change, when one is on its
    /// way. Tests use it to see what that sync did.
    func changeSyncFinished() async {
        await waiting?.value
    }

    /// Runs a sync now when someone is signed in.
    ///
    /// A call made while a sync runs does not start a second one. The sync
    /// that is running runs once more when it finishes, so a change made in
    /// the middle is not left behind.
    func sync(on model: CollectionModel) async {
        guard canSync, let engine else { return }
        guard !isSyncing else {
            isAskedAgain = true
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            let waiters = syncWaiters
            syncWaiters = []
            for waiter in waiters {
                waiter.resume()
            }
        }
        repeat {
            isAskedAgain = false
            await runOnce(engine, on: model)
            // A sync that could not start is not tried again at once.
        } while isAskedAgain && lastProblem == nil && canSync
    }

    /// Runs a sync and comes back only when one that started after this
    /// call has finished. When a sync is already running, it is asked to
    /// run once more, and this waits for that.
    private func syncAndWait(on model: CollectionModel) async {
        guard canSync else { return }
        guard isSyncing else {
            await sync(on: model)
            return
        }
        isAskedAgain = true
        await withCheckedContinuation { syncWaiters.append($0) }
    }

    private func runOnce(_ engine: SyncEngine, on model: CollectionModel) async {
        guard case .signedIn(let userID) = session.state else { return }
        // What the device remembers must describe this user's account.
        model.claimSyncLedger(for: userID)
        do {
            lastReport = try await engine.run(on: model)
            lastProblem = nil
            await refreshPosts(for: userID, on: model)
        } catch PhotoBackendError.notSignedIn {
            lastProblem = .signInEnded
        } catch PhotoBackendError.accountDeleted {
            // The photos on this device are left alone. The account may have
            // been deleted on another device, and the sign in here then ends
            // by itself when its token next needs replacing.
            lastProblem = .accountDeleted
        } catch {
            #if DEBUG
            print("SyncCoordinator: The sync could not run. \(error)")
            #endif
            lastProblem = .unavailable
        }
    }

    // MARK: Posting

    /// Asks the backend where the user's posts stand, and hands the answer
    /// to the collection. A failure leaves what was last heard, and the
    /// next sync asks again.
    private func refreshPosts(for userID: String, on model: CollectionModel) async {
        guard let posts else { return }
        let cleared = model.timesCleared
        do {
            let listing = try await posts.listPosts()
            // An answer for an account that has since signed out, or for
            // photos that were cleared meanwhile, is dropped.
            guard model.timesCleared == cleared, case .signedIn(let current) = session.state, current == userID
            else { return }
            model.takePostListing(listing)
            await bringShowingsInLine(for: userID, on: model)
        } catch {
            #if DEBUG
            print("SyncCoordinator: The posts could not be listed. \(error)")
            #endif
        }
    }

    /// Posts one of the user's photos for votes.
    ///
    /// The photo is synced first, because the backend posts only a photo
    /// whose record and image it already holds. Other users are shown the
    /// image and nothing else. Posting never looks at the technical check,
    /// which is advice to the photographer.
    func post(photoID: String, on model: CollectionModel) async -> PostOutcome {
        guard let posts, case .signedIn(let userID) = session.state else { return .signInNeeded }
        guard let photo = model.photo(id: photoID), model.canBePosted(photo) else { return .photoGone }
        waiting?.cancel()
        await syncAndWait(on: model)
        let cleared = model.timesCleared
        do {
            let standing = try await posts.post(photoID: photoID)
            guard model.timesCleared == cleared, case .signedIn(let current) = session.state, current == userID
            else { return .couldNotPost }
            model.takePostStanding(standing, forPhotoID: photoID)
            // A photo whose owner disclosed its spot goes on that spot's
            // page, which shows it once it is graded. The post stands
            // whether or not this works, and the photo's own screen offers
            // it again.
            _ = await showAtSpot(photoID: photoID, on: model)
            return .posted
        } catch PhotoBackendError.notSignedIn {
            lastProblem = .signInEnded
            return .signInNeeded
        } catch PhotoBackendError.photoNotSaved {
            return .notSavedYet
        } catch PhotoBackendError.imageHasLocation {
            return .imageHasLocation
        } catch PhotoBackendError.photoDeleted {
            return .photoGone
        } catch PhotoBackendError.accountDeleted {
            lastProblem = .accountDeleted
            return .couldNotPost
        } catch {
            #if DEBUG
            print("SyncCoordinator: The photo could not be posted. \(error)")
            #endif
            return .couldNotPost
        }
    }

    // MARK: Showing a photo at its spot

    /// Puts one posted photo on the page of the spot it was taken from.
    ///
    /// The owner chose this, by posting a photo whose spot they disclosed
    /// or by asking for it on the photo's screen. The backend is sent the
    /// spot's id, the aircraft type, and the airline, and nothing else. A
    /// photo whose location is private is never sent.
    func showAtSpot(photoID: String, on model: CollectionModel) async -> SpotShowOutcome {
        guard let posts, case .signedIn(let userID) = session.state else { return .signInNeeded }
        guard let photo = model.photo(id: photoID), !photo.isLocationUndisclosed,
              model.postStandings[photoID] != nil
        else { return .cannotShow }
        guard let showing = model.spotShowing(for: photo) else { return .spotNotListed }
        let cleared = model.timesCleared
        do {
            let kept = try await posts.show(photoID: photoID, at: showing)
            guard model.timesCleared == cleared, case .signedIn(let current) = session.state, current == userID
            else { return .couldNotChange }
            model.takeSpotShowing(kept, forPhotoID: photoID)
            return .done
        } catch PhotoBackendError.notSignedIn {
            lastProblem = .signInEnded
            return .signInNeeded
        } catch PhotoBackendError.notPosted, PhotoBackendError.photoDeleted {
            return .cannotShow
        } catch PhotoBackendError.unknownSpot {
            return .spotNotListed
        } catch {
            #if DEBUG
            print("SyncCoordinator: The photo could not be shown at its spot. \(error)")
            #endif
            return .couldNotChange
        }
    }

    /// Takes one photo off its spot's page. The post and its grade stay.
    func takeOffSpot(photoID: String, on model: CollectionModel) async -> SpotShowOutcome {
        guard let posts, case .signedIn(let userID) = session.state else { return .signInNeeded }
        let cleared = model.timesCleared
        do {
            try await posts.hide(photoID: photoID)
            guard model.timesCleared == cleared, case .signedIn(let current) = session.state, current == userID
            else { return .couldNotChange }
            model.takeSpotShowing(nil, forPhotoID: photoID)
            return .done
        } catch PhotoBackendError.notSignedIn {
            lastProblem = .signInEnded
            return .signInNeeded
        } catch {
            #if DEBUG
            print("SyncCoordinator: The photo could not be taken off its spot. \(error)")
            #endif
            return .couldNotChange
        }
    }

    /// Brings each spot's page in line with the photo it shows, after the
    /// backend has said where the user's photos are shown.
    ///
    /// A photo whose location is private is taken off. A photo whose
    /// aircraft details changed, or whose aircraft is now blocked, has the
    /// words beside it replaced. The spot itself is left as the owner set
    /// it, and nothing here puts a photo on a page it was not on.
    private func bringShowingsInLine(for userID: String, on model: CollectionModel) async {
        guard let posts else { return }
        let cleared = model.timesCleared
        for (photoID, showing) in model.spotShowings {
            guard let photo = model.photo(id: photoID) else { continue }
            let details = model.shownDetails(for: photo)
            let wanted = SpotShowing(
                spotID: showing.spotID,
                aircraftType: details.aircraftType,
                airline: details.airline
            )
            guard photo.isLocationUndisclosed || wanted != showing else { continue }
            do {
                var kept: SpotShowing?
                if photo.isLocationUndisclosed {
                    try await posts.hide(photoID: photoID)
                } else {
                    kept = try await posts.show(photoID: photoID, at: wanted)
                }
                // An answer for an account that has since signed out, or
                // for photos that were cleared meanwhile, is dropped.
                guard model.timesCleared == cleared, case .signedIn(let current) = session.state,
                      current == userID
                else { return }
                model.takeSpotShowing(kept, forPhotoID: photoID)
            } catch PhotoBackendError.unknownSpot, PhotoBackendError.notPosted, PhotoBackendError.photoDeleted {
                // This page cannot be changed now. The others still can.
                continue
            } catch {
                // The next sync tries again.
                #if DEBUG
                print("SyncCoordinator: A spot's page could not be brought in line. \(error)")
                #endif
                return
            }
        }
    }

    // MARK: Deleting the account

    /// Deletes every photo on this device, and the account on the backend
    /// when someone is signed in.
    ///
    /// The request to delete the account is saved first and the device is
    /// cleared second, so the backend's copies can never be fetched back.
    /// The backend is told last. If that fails, the delete stays owed and is
    /// sent again when the app next comes to the front.
    ///
    /// - Returns: False when nothing was removed, because the request could
    ///   not be saved. The user can try again.
    @discardableResult
    func deleteAccountAndPhotos(on model: CollectionModel) async -> Bool {
        waiting?.cancel()
        // With no backend there is no account to delete.
        if session.isSignedIn, backend != nil {
            do {
                try session.beginAccountDelete()
            } catch {
                #if DEBUG
                print("SyncCoordinator: The request to delete the account could not be saved. \(error)")
                #endif
                return false
            }
        }
        model.deleteAccountAndPhotos(alsoOnBackend: session.isAccountDeleteOwed)
        await sendAccountDeleteIfOwed()
        return true
    }

    /// Tells the backend to delete the account when that is still owed.
    func sendAccountDeleteIfOwed() async {
        guard session.isAccountDeleteOwed, let backend, !isSendingAccountDelete else { return }
        isSendingAccountDelete = true
        defer { isSendingAccountDelete = false }
        for _ in 0..<max(1, pacing.accountDeleteAttempts) {
            do {
                try await backend.deleteAccount()
                session.finishAccountDelete()
                return
            } catch PhotoBackendError.unavailable(status: _) {
                // The backend failed or ran out of time partway. It picks up
                // where it stopped, so the request is sent again.
                continue
            } catch {
                // With no network the delete stays owed. When the sign in
                // itself has stopped working, the session has already
                // forgotten it, which happens once the account is gone and
                // its last token has run out. Nothing is owed then.
                #if DEBUG
                print("SyncCoordinator: The account delete was not confirmed. \(error)")
                #endif
                return
            }
        }
    }
}

extension SyncCoordinator {
    /// The coordinator the app uses, made from this build's settings. A
    /// build with no backend gets one that cannot sign in and never syncs.
    static func forThisBuild() -> SyncCoordinator {
        let transport = URLSessionTransport.standard
        var identity: (any IdentityService)?
        if let authURL = AppEnvironment.authBaseURL, let clientID = AppEnvironment.authClientID {
            identity = CognitoIdentityService(baseURL: authURL, clientID: clientID, transport: transport)
        }
        let session = AccountSession(
            identity: identity,
            store: KeychainSessionStore.forThisBuild
        )
        var backend: (any PhotoBackend)?
        var posts: (any PostBackend)?
        if let apiURL = AppEnvironment.apiBaseURL {
            backend = HTTPPhotoBackend(
                baseURL: apiURL,
                transport: transport,
                accessToken: { try await session.accessToken() }
            )
            posts = HTTPPostBackend(
                baseURL: apiURL,
                transport: transport,
                accessToken: { try await session.accessToken() }
            )
        }
        return SyncCoordinator(session: session, backend: backend, posts: posts, pacing: SyncPacing())
    }

    /// Who a preview shows.
    enum PreviewAccount {
        /// A build with no backend, where signing in is not offered.
        case noBackend
        case signedOut
        case signedIn
        case deletingAccount
    }

    /// A coordinator on sample services, for previews. Nothing it does
    /// leaves the device.
    static func preview(_ account: PreviewAccount = .noBackend) -> SyncCoordinator {
        let saved: StoredSession?
        switch account {
        case .noBackend, .signedOut:
            saved = nil
        case .signedIn, .deletingAccount:
            saved = StoredSession(
                userID: "sample-user",
                tokens: SessionTokens(
                    accessToken: "sample-access",
                    refreshToken: "sample-refresh",
                    accessTokenExpiresAt: .distantFuture
                ),
                isAccountDeleteOwed: account == .deletingAccount
            )
        }
        let hasBackend = account != .noBackend
        let photos = SamplePhotoBackend()
        let identity = SampleIdentityService()
        identity.testAccounts = [SampleData.testAccountName: SampleData.testAccountPassword]
        return SyncCoordinator(
            session: AccountSession(
                identity: hasBackend ? identity : nil,
                store: MemorySessionStore(saved)
            ),
            backend: hasBackend ? photos : nil,
            posts: hasBackend ? SamplePostBackend(photos: photos) : nil,
            pacing: SyncPacing()
        )
    }
}
