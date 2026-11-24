import Foundation

/// Sends one request and returns the answer. It sits behind a protocol so
/// the backend code can be tested with no network.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The transport the app uses.
struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    /// A session that keeps nothing on the device. Answers hold the user's
    /// records and short lived links, so none of it is cached, and no
    /// cookies are kept.
    static var standard: URLSessionTransport {
        URLSessionTransport(session: URLSession(configuration: .ephemeral))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PhotoBackendError.unreadableAnswer
        }
        return (data, http)
    }
}
