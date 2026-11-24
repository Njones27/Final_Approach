import Foundation
import Testing

@testable import FinalApproachCore

@Suite struct SyncPlanTests {
    private func here(_ id: String, _ fingerprint: String = "f1", image: Bool = true) -> LocalPhotoState {
        LocalPhotoState(id: id, fingerprint: fingerprint, hasImage: image)
    }

    private func there(_ id: String, _ version: String = "v1") -> RemotePhotoState {
        RemotePhotoState(id: id, version: version)
    }

    private func agreed(_ fingerprint: String = "f1", _ version: String = "v1", image: Bool = true) -> SyncRecord {
        SyncRecord(localFingerprint: fingerprint, remoteVersion: version, imageSent: image)
    }

    private func plan(
        local: [LocalPhotoState] = [],
        remote: [RemotePhotoState] = [],
        deleted: Set<String> = [],
        ledger: SyncLedger = SyncLedger()
    ) -> [SyncAction] {
        SyncPlan.actions(local: local, remote: remote, remoteDeleted: deleted, ledger: ledger)
    }

    // MARK: Nothing to do

    @Test func nothingAnywhereNeedsNothing() {
        #expect(plan().isEmpty)
    }

    @Test func aPhotoBothSidesAgreeOnNeedsNothing() {
        let ledger = SyncLedger(records: ["a": agreed()])
        #expect(plan(local: [here("a")], remote: [there("a")], ledger: ledger).isEmpty)
    }

    // MARK: Uploads

    @Test func aNewPhotoIsSentWithItsImage() {
        #expect(plan(local: [here("a")]) == [.upload(id: "a", withImage: true)])
    }

    @Test func aNewPhotoWithNoImageIsSentAlone() {
        #expect(plan(local: [here("a", image: false)]) == [.upload(id: "a", withImage: false)])
    }

    @Test func anEditedPhotoIsSentWithoutTheImageTheBackendHas() {
        let ledger = SyncLedger(records: ["a": agreed("f1")])
        let actions = plan(local: [here("a", "f2")], remote: [there("a")], ledger: ledger)
        #expect(actions == [.upload(id: "a", withImage: false)])
    }

    @Test func anImageThatNeverArrivedIsSentAgain() {
        let ledger = SyncLedger(records: ["a": agreed(image: false)])
        let actions = plan(local: [here("a")], remote: [there("a")], ledger: ledger)
        #expect(actions == [.upload(id: "a", withImage: true)])
    }

    @Test func aPhotoTheBackendLostIsSentAgain() {
        let ledger = SyncLedger(records: ["a": agreed()])
        #expect(plan(local: [here("a")], ledger: ledger) == [.upload(id: "a", withImage: true)])
    }

    @Test func aPhotoEditedOnBothSidesSendsTheDevicesCopy() {
        let ledger = SyncLedger(records: ["a": agreed("f1", "v1")])
        let actions = plan(local: [here("a", "f2")], remote: [there("a", "v2")], ledger: ledger)
        #expect(actions == [.upload(id: "a", withImage: false)])
    }

    @Test func anUploadWhoseAnswerWasLostIsSentAgain() {
        var ledger = SyncLedger()
        ledger.noteUploadStarted(id: "a")
        let actions = plan(local: [here("a")], remote: [there("a")], ledger: ledger)
        #expect(actions == [.upload(id: "a", withImage: true)])
    }

    // MARK: Downloads

    @Test func aPhotoFromAnotherDeviceIsFetchedWithItsImage() {
        #expect(plan(remote: [there("a")]) == [.download(id: "a", withImage: true)])
    }

    @Test func aPhotoEditedOnAnotherDeviceIsFetchedWithoutTheImageTheDeviceHas() {
        let ledger = SyncLedger(records: ["a": agreed("f1", "v1")])
        let actions = plan(local: [here("a")], remote: [there("a", "v2")], ledger: ledger)
        #expect(actions == [.download(id: "a", withImage: false)])
    }

    @Test func aRecordWithNoImageOnTheDeviceFetchesItsImage() {
        let ledger = SyncLedger(records: ["a": agreed()])
        let actions = plan(local: [here("a", image: false)], remote: [there("a")], ledger: ledger)
        #expect(actions == [.fetchImage(id: "a")])
    }

    // MARK: Deletes

    @Test func aPhotoDeletedHereIsDeletedOnTheBackend() {
        let ledger = SyncLedger(pendingDeletes: ["a"])
        #expect(plan(remote: [there("a")], ledger: ledger) == [.deleteRemote(id: "a")])
    }

    @Test func aPendingDeleteIsSentEvenWhenTheBackendDoesNotListThePhoto() {
        // The record may have gone while its image is still there.
        let ledger = SyncLedger(pendingDeletes: ["a"])
        #expect(plan(ledger: ledger) == [.deleteRemote(id: "a")])
    }

    @Test func aPhotoDeletedHereIsNeverFetchedBack() {
        let ledger = SyncLedger(pendingDeletes: ["a"])
        let actions = plan(remote: [there("a")], ledger: ledger)
        #expect(!actions.contains(.download(id: "a", withImage: true)))
    }

    @Test func aPhotoDeletedElsewhereIsRemovedFromTheDevice() {
        let ledger = SyncLedger(records: ["a": agreed()])
        let actions = plan(local: [here("a")], deleted: ["a"], ledger: ledger)
        #expect(actions == [.deleteLocal(id: "a")])
    }

    @Test func aPhotoDeletedElsewhereIsNotSentAgainEvenWhenEditedHere() {
        let ledger = SyncLedger(records: ["a": agreed("f1")])
        let actions = plan(local: [here("a", "f2")], deleted: ["a"], ledger: ledger)
        #expect(actions == [.deleteLocal(id: "a")])
    }

    @Test func aPhotoDeletedOnBothSidesNeedsNoRequest() {
        let ledger = SyncLedger(pendingDeletes: ["a"])
        #expect(plan(deleted: ["a"], ledger: ledger).isEmpty)
    }

    @Test func aDeleteTheDeviceNeverHadNeedsNothing() {
        #expect(plan(deleted: ["a"]).isEmpty)
    }

    // MARK: Order

    @Test func deletesComeFirstAndEachGroupIsSortedByID() {
        let ledger = SyncLedger(
            records: ["kept": agreed(), "goneThere": agreed()],
            pendingDeletes: ["goneHere2", "goneHere1"]
        )
        let actions = plan(
            local: [here("new2"), here("kept"), here("goneThere"), here("new1")],
            remote: [there("kept"), there("other2"), there("other1")],
            deleted: ["goneThere"],
            ledger: ledger
        )
        #expect(actions == [
            .deleteRemote(id: "goneHere1"),
            .deleteRemote(id: "goneHere2"),
            .deleteLocal(id: "goneThere"),
            .upload(id: "new1", withImage: true),
            .upload(id: "new2", withImage: true),
            .download(id: "other1", withImage: true),
            .download(id: "other2", withImage: true),
        ])
    }
}

@Suite struct SyncLedgerTests {
    @Test func anUploadIsRemembered() {
        var ledger = SyncLedger()
        ledger.noteUploadStarted(id: "a")
        ledger.noteUploaded(id: "a", fingerprint: "f1", version: "v1", imageSent: true)
        #expect(ledger.records["a"] == SyncRecord(localFingerprint: "f1", remoteVersion: "v1", imageSent: true))
    }

    @Test func startingAnUploadDoesNotForgetWhatWasAgreed() {
        var ledger = SyncLedger()
        ledger.noteUploaded(id: "a", fingerprint: "f1", version: "v1", imageSent: true)
        ledger.noteUploadStarted(id: "a")
        #expect(ledger.records["a"] == SyncRecord(localFingerprint: "f1", remoteVersion: "v1", imageSent: true))
    }

    @Test func anImageSentEarlierStaysCountedAfterAnEdit() {
        var ledger = SyncLedger()
        ledger.noteUploaded(id: "a", fingerprint: "f1", version: "v1", imageSent: true)
        ledger.noteUploaded(id: "a", fingerprint: "f2", version: "v2", imageSent: false)
        #expect(ledger.records["a"] == SyncRecord(localFingerprint: "f2", remoteVersion: "v2", imageSent: true))
    }

    @Test func aDownloadWithItsImageShowsTheBackendHoldsTheImage() {
        var ledger = SyncLedger()
        ledger.noteDownloaded(id: "a", fingerprint: "f1", version: "v1", imageFetched: true)
        #expect(ledger.records["a"]?.imageSent == true)
    }

    @Test func aDownloadWithoutItsImageDoesNotClaimTheBackendHoldsIt() {
        var ledger = SyncLedger()
        ledger.noteDownloaded(id: "a", fingerprint: "f1", version: "v1", imageFetched: false)
        #expect(ledger.records["a"]?.imageSent == false)
        ledger.noteImageFetched(id: "a")
        #expect(ledger.records["a"]?.imageSent == true)
    }

    @Test func deletingASentPhotoLeavesAPendingDelete() {
        var ledger = SyncLedger()
        ledger.noteUploaded(id: "a", fingerprint: "f1", version: "v1", imageSent: true)
        ledger.noteDeletedHere(id: "a")
        #expect(ledger.records["a"] == nil)
        #expect(ledger.pendingDeletes == ["a"])
    }

    @Test func deletingAPhotoWhoseUploadOnlyStartedStillLeavesAPendingDelete() {
        // The upload may have reached the backend with its answer lost.
        var ledger = SyncLedger()
        ledger.noteUploadStarted(id: "a")
        ledger.noteDeletedHere(id: "a")
        #expect(ledger.pendingDeletes == ["a"])
    }

    @Test func deletingAPhotoThatWasNeverSentLeavesNoTrace() {
        var ledger = SyncLedger()
        ledger.noteDeletedHere(id: "a")
        #expect(ledger == SyncLedger())
    }

    @Test func aSettledDeleteIsForgotten() {
        var ledger = SyncLedger(
            records: ["a": SyncRecord(localFingerprint: "f1", remoteVersion: "v1", imageSent: true)],
            pendingDeletes: ["a"]
        )
        ledger.noteDeleteSettled(id: "a")
        #expect(ledger == SyncLedger())
    }

    @Test func theLedgerSurvivesBeingSavedAndRead() throws {
        var ledger = SyncLedger()
        ledger.noteUploaded(id: "a", fingerprint: "f1", version: "v1", imageSent: true)
        ledger.noteUploaded(id: "b", fingerprint: "f2", version: "v2", imageSent: false)
        ledger.noteDeletedHere(id: "b")
        let data = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(SyncLedger.self, from: data) == ledger)
    }

    // MARK: Whose ledger it is

    private func sent(_ id: String, into ledger: inout SyncLedger) {
        ledger.noteUploaded(id: id, fingerprint: "f1", version: "v1", imageSent: true)
    }

    @Test func aLedgerSavedBeforeItHadAnOwnerStillOpens() throws {
        let saved = Data(#"{"records":{},"pendingDeletes":["a"]}"#.utf8)
        let ledger = try JSONDecoder().decode(SyncLedger.self, from: saved)
        #expect(ledger == SyncLedger(pendingDeletes: ["a"]))
    }

    @Test func theOwnerAndTheParkedDeletesSurviveBeingSavedAndRead() throws {
        let ledger = SyncLedger(pendingDeletes: ["a"], owner: "user-1", parkedDeletes: ["user-2": ["b"]])
        let data = try JSONEncoder().encode(ledger)
        let read = try JSONDecoder().decode(SyncLedger.self, from: data)
        #expect(read == ledger)
    }

    @Test func aLedgerWithNoOwnerBecomesTheFirstUsers() {
        var ledger = SyncLedger()
        ledger.claim(for: "user-1")
        #expect(ledger == SyncLedger(owner: "user-1"))
    }

    @Test func claimingALedgerAgainChangesNothing() {
        var ledger = SyncLedger(owner: "user-1")
        sent("a", into: &ledger)
        sent("b", into: &ledger)
        ledger.noteDeletedHere(id: "b")
        let before = ledger
        ledger.claim(for: "user-1")
        #expect(ledger == before)
    }

    @Test func anotherUserStartsTheLedgerAgain() {
        var ledger = SyncLedger(owner: "user-1")
        sent("a", into: &ledger)
        ledger.claim(for: "user-2")
        #expect(ledger == SyncLedger(owner: "user-2"))
    }

    @Test func aDeleteOwedToOneUserIsNeverSentForAnother() {
        var ledger = SyncLedger(owner: "user-1")
        sent("a", into: &ledger)
        ledger.noteDeletedHere(id: "a")

        ledger.claim(for: "user-2")

        #expect(ledger.pendingDeletes.isEmpty)
        #expect(ledger.parkedDeletes == ["user-1": ["a"]])
        let plan = SyncPlan.actions(local: [], remote: [], remoteDeleted: [], ledger: ledger)
        #expect(plan.isEmpty)
    }

    @Test func aParkedDeleteComesBackWhenItsUserSignsInAgain() {
        var ledger = SyncLedger(owner: "user-1")
        sent("a", into: &ledger)
        ledger.noteDeletedHere(id: "a")
        ledger.claim(for: "user-2")
        sent("b", into: &ledger)
        ledger.noteDeletedHere(id: "b")

        ledger.claim(for: "user-1")

        #expect(ledger.owner == "user-1")
        #expect(ledger.pendingDeletes == ["a"])
        #expect(ledger.parkedDeletes == ["user-2": ["b"]])
        let plan = SyncPlan.actions(local: [], remote: [], remoteDeleted: [], ledger: ledger)
        #expect(plan == [.deleteRemote(id: "a")])
    }

    @Test func clearingTheDeviceWithTheAccountOwesThatAccountNothing() {
        var ledger = SyncLedger(owner: "user-1", parkedDeletes: ["user-1": ["old"], "user-2": ["b"]])
        sent("a", into: &ledger)
        sent("c", into: &ledger)
        ledger.noteDeletedHere(id: "c")

        ledger.noteDeviceCleared(accountDeleted: true)

        #expect(ledger == SyncLedger(parkedDeletes: ["user-2": ["b"]]))
    }

    @Test func clearingOnlyTheDeviceKeepsTheDeletesTheAccountIsOwed() {
        var ledger = SyncLedger(owner: "user-1")
        sent("a", into: &ledger)
        sent("c", into: &ledger)
        ledger.noteDeletedHere(id: "c")

        ledger.noteDeviceCleared(accountDeleted: false)

        // The photo that was only removed from the device is not a delete.
        #expect(ledger == SyncLedger(parkedDeletes: ["user-1": ["c"]]))
        ledger.claim(for: "user-1")
        #expect(ledger.pendingDeletes == ["c"])
    }

    @Test func clearingADeviceNoOneSignedInOnLeavesAnEmptyLedger() {
        var ledger = SyncLedger()
        ledger.noteDeviceCleared(accountDeleted: false)
        #expect(ledger == SyncLedger())
    }

    @Test func aFullRoundOfSyncsSettles() {
        // A new photo is sent, then nothing is left to do.
        var ledger = SyncLedger()
        let local = [LocalPhotoState(id: "a", fingerprint: "f1", hasImage: true)]
        let first = SyncPlan.actions(local: local, remote: [], remoteDeleted: [], ledger: ledger)
        #expect(first == [.upload(id: "a", withImage: true)])
        ledger.noteUploadStarted(id: "a")
        ledger.noteUploaded(id: "a", fingerprint: "f1", version: "v1", imageSent: true)
        let remote = [RemotePhotoState(id: "a", version: "v1")]
        #expect(SyncPlan.actions(local: local, remote: remote, remoteDeleted: [], ledger: ledger).isEmpty)

        // The user deletes it. The backend is told, then nothing is left.
        ledger.noteDeletedHere(id: "a")
        let afterDelete = SyncPlan.actions(local: [], remote: remote, remoteDeleted: [], ledger: ledger)
        #expect(afterDelete == [.deleteRemote(id: "a")])
        ledger.noteDeleteSettled(id: "a")
        #expect(SyncPlan.actions(local: [], remote: [], remoteDeleted: ["a"], ledger: ledger).isEmpty)
    }
}
