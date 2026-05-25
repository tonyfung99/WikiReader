import Foundation

nonisolated enum AppGroup {
    static let identifier = "group.com.anifoca.WikiReader"

    /// Shared defaults across the host app and the share extension.
    /// Falls back to standard defaults if the App Group isn't configured yet,
    /// so the host app remains usable standalone during early development.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
