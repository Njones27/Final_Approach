import Foundation

@testable import FinalApproach

/// A transport that answers from a script and remembers what it was sent.
@MainActor
final class ScriptedTransport: HTTPTransport {
    struct Answer {
        var status = 200
        var body = Data()
    }

    private(set) var requests: [URLRequest] = []
    private var answers: [Answer]

    init(_ answers: [Answer]) {
        self.answers = answers
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !answers.isEmpty, let url = request.url else { throw URLError(.badServerResponse) }
        let answer = answers.removeFirst()
        guard let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return (answer.body, response)
    }
}
