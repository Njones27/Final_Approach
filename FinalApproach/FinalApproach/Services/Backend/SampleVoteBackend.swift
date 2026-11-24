import Foundation

/// Voting kept in memory, for previews and tests. It follows the real
/// backend's rules. A user votes once on a post, and a post they voted on
/// leaves their queue.
final class SampleVoteBackend: VoteBackend {
    /// One photo another user posted.
    struct Post {
        let id: String
        let image: Data
    }

    private var posts: [Post]
    private let scaleMax: Int
    /// How many posts one answer of the queue holds.
    private let queueSize: Int
    /// The votes cast so far, by post id.
    private(set) var votes: [String: Int] = [:]
    private(set) var queueCount = 0
    /// Makes every request for the queue fail with this.
    var queueFailure: PhotoBackendError?
    /// Makes the next vote fail with this, once.
    var nextCastFailure: PhotoBackendError?
    /// Posts whose voting has closed, which refuse a vote.
    var closedIDs: Set<String> = []

    init(posts: [Post], scaleMax: Int = 5, queueSize: Int = 10) {
        self.posts = posts
        self.scaleMax = scaleMax
        self.queueSize = queueSize
    }

    func queue() async throws -> VoteQueue {
        queueCount += 1
        if let queueFailure { throw queueFailure }
        let open = posts.filter { votes[$0.id] == nil }.prefix(queueSize)
        return VoteQueue(
            posts: open.map { VotePost(id: $0.id, imageURL: Self.imageURL(forPostID: $0.id)) },
            scaleMax: scaleMax
        )
    }

    func image(from url: URL) async throws -> Data? {
        posts.first { $0.id == url.lastPathComponent }?.image
    }

    func cast(_ value: Int, onPostID postID: String) async throws {
        if let failure = nextCastFailure {
            nextCastFailure = nil
            throw failure
        }
        guard (1...scaleMax).contains(value) else {
            throw PhotoBackendError.refused(status: 400, message: "A vote is a whole number of stars.")
        }
        guard posts.contains(where: { $0.id == postID }), !closedIDs.contains(postID) else {
            throw PhotoBackendError.votingClosed
        }
        guard votes[postID] == nil else { throw PhotoBackendError.alreadyVoted }
        votes[postID] = value
    }

    /// Adds a photo another user just posted.
    func add(_ post: Post) {
        posts.append(post)
    }

    /// Takes a post down, as deleting its photo does.
    func remove(postID: String) {
        posts.removeAll { $0.id == postID }
    }

    /// A stand in for the link the real backend gives to an image.
    static func imageURL(forPostID id: String) -> URL {
        URL(filePath: "/sample-backend/votes").appending(path: id)
    }
}
