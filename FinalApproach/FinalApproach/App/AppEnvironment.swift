import Foundation

/// Which backend this build talks to.
///
/// The value comes from the `APP_ENVIRONMENT` build setting in
/// `Config/App.xcconfig`, which is beta for a build made in Xcode. Xcode
/// Cloud sets it to prod for a TestFlight build through
/// `ci_scripts/ci_post_clone.sh`. A build with no setting at all is dev and
/// has no backend.
enum AppEnvironment: String {
    case dev
    case beta
    case prod

    static let current: AppEnvironment = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AppEnvironment") as? String
        return raw.flatMap(AppEnvironment.init(rawValue:)) ?? .dev
    }()

    /// The backend host for this build, or nil while no backend exists.
    static let apiHost: String? = setting("APIHost")

    /// The address of the backend's API for this build, or nil while the
    /// build has no backend.
    static let apiBaseURL: URL? = apiHost.flatMap { baseURL(forHost: $0) }

    /// The address the app signs in at, or nil while the build has no
    /// backend.
    static let authBaseURL: URL? = setting("AuthHost").flatMap { baseURL(forHost: $0) }

    /// The id the user pool gave the app, or nil while the build has no
    /// backend. It ships inside the app and is not a secret.
    static let authClientID: String? = setting("AuthClientID").flatMap { clientID(from: $0) }

    /// One value from the build settings, or nil when it is empty.
    private nonisolated static func setting(_ key: String) -> String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// The app client id when the text is one. A user pool makes its ids
    /// from letters and digits, so anything else is a mistyped setting.
    nonisolated static func clientID(from text: String) -> String? {
        let isPlain = text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return !text.isEmpty && isPlain ? text : nil
    }

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
