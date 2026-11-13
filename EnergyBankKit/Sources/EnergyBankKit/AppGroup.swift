import Foundation

/// The App Group shared by the app and its extensions (Screen Time monitor, later the widget).
/// Must match `com.apple.security.application-groups` in project.yml.
public enum AppGroup {
    public static let identifier = "group.com.kalisoft.energybank"

    #if canImport(Darwin)
    /// The shared container, or nil when the entitlement is missing (e.g. in unit tests).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
    #endif
}
