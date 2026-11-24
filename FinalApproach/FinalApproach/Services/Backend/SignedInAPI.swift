import Foundation

/// Sends requests to the API as the signed in user. The routes are in
/// `docs/backend.md`.
struct SignedInAPI {
    /// The address of the API, with no path.
    let baseURL: URL
    let transport: any HTTPTransport
    /// Gives the token that proves who is signed in. It throws
    /// `PhotoBackendError.notSignedIn` when no one is.
    let accessToken: () async throws -> String

    /// Sends a request and returns the body of a successful answer.
    func call(_ method: String, _ url: URL, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.problem(status: response.statusCode, body: data)
        }
        return data
    }

    func decode<Answer: Decodable>(_ data: Data) throws -> Answer {
        do {
            return try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw PhotoBackendError.unreadableAnswer
        }
    }

    /// Turns a refusal into the error the app acts on. The backend sends a
    /// code for the refusals that share a status.
    static func problem(status: Int, body: Data) -> PhotoBackendError {
        let answer = try? JSONDecoder().decode(ProblemAnswer.self, from: body)
        switch (status, answer?.code) {
        case (401, _), (_, "notSignedIn"):
            return .notSignedIn
        case (_, "photoDeleted"):
            return .photoDeleted
        case (_, "accountDeleted"):
            return .accountDeleted
        case (_, "photoNotSaved"):
            return .photoNotSaved
        case (_, "imageHasLocation"):
            return .imageHasLocation
        case (_, "alreadyVoted"):
            return .alreadyVoted
        case (_, "votingClosed"):
            return .votingClosed
        case (_, "ownPost"):
            return .ownPost
        case (500..., _):
            return .unavailable(status: status)
        default:
            return .refused(status: status, message: answer?.message ?? "")
        }
    }
}

private struct ProblemAnswer: Decodable {
    let message: String?
    let code: String?
}
