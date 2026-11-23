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

    var displayName: String {
        switch self {
        case .dev: "Development"
        case .beta: "Beta"
        case .prod: "Production"
        }
    }
}
