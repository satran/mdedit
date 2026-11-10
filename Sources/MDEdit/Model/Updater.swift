import AppKit

/// Tells the person when a newer release is on GitHub. It only looks and opens the releases page in the browser;
/// it never downloads or installs anything. One GET to the public releases API, no identifier, no cookies.
@MainActor
final class Updater {
    static let shared = Updater()

    static let website = URL(string: "https://mdedit.satran.in/")!
    static let releasesPage = URL(string: "https://github.com/satran/mdedit/releases/latest")!
    static let latestRelease = URL(string: "https://api.github.com/repos/satran/mdedit/releases/latest")!
    static let interval: TimeInterval = 24 * 3600

    struct Release: Equatable { let version: String; let page: URL }
    enum Outcome: Equatable { case newer(Release), current, failed }

    private let defaults: UserDefaults
    private let fetch: (URL) async throws -> Data
    private var running = false

    init(defaults: UserDefaults = AppEnvironment.defaults,
         fetch: @escaping (URL) async throws -> Data = Updater.download) {
        self.defaults = defaults
        self.fetch = fetch
    }

    nonisolated static func download(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        let (data, response) = try await URLSession(configuration: cfg).data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { throw URLError(.badServerResponse) }
        return data
    }

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// "v0.3.1" → [0, 3, 1]; nil when it is not a plain dotted number.
    nonisolated static func parts(_ tag: String) -> [Int]? {
        let t = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let p = t.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        return p.isEmpty || p.contains(where: { $0 == nil }) ? nil : p.compactMap { $0 }
    }

    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        guard var r = parts(remote), var l = parts(local) else { return false }
        while r.count < l.count { r.append(0) }
        while l.count < r.count { l.append(0) }
        return r.lexicographicallyPrecedes(l) == false && r != l
    }

    /// The latest published release, from the GitHub API's answer. Pre-releases and drafts are not offered.
    nonisolated static func release(from data: Data) -> Release? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = o["tag_name"] as? String, parts(tag) != nil,
              o["draft"] as? Bool != true, o["prerelease"] as? Bool != true else { return nil }
        // the page always lives on the repository's own releases, whatever the answer says
        let page = URL(string: "https://github.com/satran/mdedit/releases/tag/" + tag) ?? releasesPage
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page)
    }

    func check() async -> Outcome {
        guard let data = try? await fetch(Self.latestRelease), let rel = Self.release(from: data) else { return .failed }
        defaults.set(Date(), forKey: "lastUpdateCheck")
        return Self.isNewer(rel.version, than: currentVersion) ? .newer(rel) : .current
    }

    /// At launch: once a day, quietly. Says something only when there is a newer version.
    func checkInBackground(prefs: Preferences) {
        guard prefs.checkForUpdates, !AppEnvironment.isTesting, !running else { return }
        if let last = defaults.object(forKey: "lastUpdateCheck") as? Date, Date().timeIntervalSince(last) < Self.interval { return }
        running = true
        Task {
            let outcome = await check()
            running = false
            if case .newer(let rel) = outcome { offer(rel) }
        }
    }

    /// From the menu: always answers.
    func checkNow() {
        guard !running else { return }
        running = true
        Task {
            let outcome = await check()
            running = false
            switch outcome {
            case .newer(let rel): offer(rel)
            case .current: say("MDEdit is up to date", "You have version \(currentVersion), the latest.")
            case .failed: say("Could not check for updates", "MDEdit could not reach github.com. Try again later, or look at the releases page.", releases: true)
            }
        }
    }

    private func offer(_ rel: Release) {
        let a = NSAlert()
        a.messageText = "MDEdit \(rel.version) is available"
        a.informativeText = "You have version \(currentVersion). Download opens the release page in your browser."
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(rel.page) }
    }

    private func say(_ title: String, _ text: String, releases: Bool = false) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        if releases { a.addButton(withTitle: "Releases Page") }
        if a.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(Self.releasesPage) }
    }

    // MARK: About

    static let blurb = "A Markdown editor for the Mac. Open a folder, link notes with [[wiki links]], search the whole folder, and keep every note as plain text."

    static func showAbout() {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let credits = NSMutableAttributedString(string: blurb + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: style, .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(string: "mdedit.satran.in", attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: style, .link: website]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "MDEdit"])
        NSApp.activate(ignoringOtherApps: true)
    }
}
