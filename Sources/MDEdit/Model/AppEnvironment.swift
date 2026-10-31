import Foundation

/// Where the app keeps its settings. While the tests run (the app hosts them) everything goes to a scratch
/// domain, so a test run never reads or changes the real folders, recent list or preferences.
enum AppEnvironment {
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static let defaults: UserDefaults = {
        guard isTesting, let d = UserDefaults(suiteName: "in.ranjeev.mdedit.tests") else { return .standard }
        d.removePersistentDomain(forName: "in.ranjeev.mdedit.tests")
        return d
    }()
}
