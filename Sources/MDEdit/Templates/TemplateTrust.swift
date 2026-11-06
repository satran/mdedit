import Foundation

/// The first Render in the app shows a warning once (a rendered page can read every note in the folder); after that Render just renders.
/// The answer is kept in the app's settings, never in a folder.
enum TemplateTrust {
    static let key = "templateWarned"
    static func hasBeenWarned(defaults: UserDefaults) -> Bool { defaults.bool(forKey: key) }
    static func markWarned(defaults: UserDefaults) { defaults.set(true, forKey: key) }
}
