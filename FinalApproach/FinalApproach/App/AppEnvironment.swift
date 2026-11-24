import Foundation

/// Which backend this build talks to.
///
/// The value comes from the `APP_ENVIRONMENT` build setting in
/// `Config/App.xcconfig`. Xcode Cloud overrides it for beta and prod builds
/// through `ci_scripts/ci_post_clone.sh`.
enum AppEnvironment: String {
    case dev
    case beta
    case prod

    static let current: AppEnvironment = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AppEnvironment") as? String
        return raw.flatMap(AppEnvironment.init(rawValue:)) ?? .dev
    }()

    /// The backend host for this build, or nil while no backend exists.
    static let apiHost: String? = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APIHost") as? String
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }()

    /// The address of the backend's API for this build, or nil while the
    /// build has no backend.
    static let apiBaseURL: URL? = apiHost.flatMap { baseURL(forHost: $0) }

    /// The HTTPS address for a bare host name. A value that is not a plain
    /// host name gives nil, so a mistyped setting cannot point the app at an
    /// address with a path or a sign in inside it.
    static func baseURL(forHost host: String) -> URL? {
        let isPlainHost = host.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-")
        }
        guard !host.isEmpty, isPlainHost else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        return parts.url
    }

    var displayName: String {
        switch self {
        case .dev: "Development"
        case .beta: "Beta"
        case .prod: "Production"
        }
    }
}
