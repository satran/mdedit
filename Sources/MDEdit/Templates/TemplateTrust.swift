import Foundation

/// The first Render in the app shows a warning once (a rendered page can read every note in the folder); after that Render just renders.
/// The answer is kept in the app's settings, never in a folder.
///
/// Also the web addresses a person has chosen to open from a rendered page without being asked (per folder, in the app's settings, so a
/// received folder cannot trust a host for itself). Only `https`, only the host: `example.com` is that host alone, `*.example.com` is any
/// host below it. A user name or a port in the address means it is not trusted.
enum TemplateTrust {
    static let key = "templateWarned"
    static func hasBeenWarned(defaults: UserDefaults) -> Bool { defaults.bool(forKey: key) }
    static func markWarned(defaults: UserDefaults) { defaults.set(true, forKey: key) }

    // MARK: pages that were rendered

    /// A page the person has pressed Render on is rendered again, without a click, when it is opened and its text is exactly what it was
    /// then. The record is a SHA-256 of the text per folder and path, in the app's settings (never in a folder, which could vouch for
    /// itself): at most 200 files per folder and 50 folders, the least recently rendered dropped first. Any edit makes the page ask again.
    static let maxFiles = 200
    static let maxRoots = 50
    static let rootsKey = "templateRenderedRoots"

    private static func renderedKey(_ root: URL) -> String { "templateRendered:" + root.resolvingSymlinksInPath().path }

    private static func rendered(_ root: URL, _ defaults: UserDefaults) -> [[String]] { (defaults.array(forKey: renderedKey(root)) as? [[String]]) ?? [] }

    static func wasRendered(_ path: String, text: String, root: URL, defaults: UserDefaults) -> Bool {
        let hash = ContentHash.sha256(text)
        return rendered(root, defaults).contains { $0.count == 2 && $0[0] == path && $0[1] == hash }
    }

    static func markRendered(_ path: String, text: String, root: URL, defaults: UserDefaults) {
        var list = rendered(root, defaults).filter { $0.first != path }
        list.insert([path, ContentHash.sha256(text)], at: 0)
        let k = renderedKey(root)
        defaults.set(Array(list.prefix(maxFiles)), forKey: k)
        var roots = (defaults.stringArray(forKey: rootsKey) ?? []).filter { $0 != k }
        roots.insert(k, at: 0)
        for dropped in roots.dropFirst(maxRoots) { defaults.removeObject(forKey: dropped) }
        defaults.set(Array(roots.prefix(maxRoots)), forKey: rootsKey)
    }

    static let maxHosts = 50

    private static func hostsKey(_ root: URL) -> String { "templateTrustedHosts:" + root.resolvingSymlinksInPath().path }

    static func trustedHosts(root: URL, defaults: UserDefaults) -> [String] { defaults.stringArray(forKey: hostsKey(root)) ?? [] }

    /// One host per entry; anything that is not a plain host name (or `*.` and a host name) is dropped.
    static func normalized(_ lines: [String]) -> [String] {
        var out: [String] = []
        for raw in lines {
            let h = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard !h.isEmpty, h.count <= 100, !out.contains(h) else { continue }
            let name = h.hasPrefix("*.") ? String(h.dropFirst(2)) : h
            let labels = name.split(separator: ".", omittingEmptySubsequences: false)
            guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else { continue }
            out.append(h)
        }
        return Array(out.prefix(maxHosts))
    }

    static func setTrustedHosts(_ lines: [String], root: URL, defaults: UserDefaults) {
        let list = normalized(lines)
        if list.isEmpty { defaults.removeObject(forKey: hostsKey(root)) } else { defaults.set(list, forKey: hostsKey(root)) }
    }

    static func isTrusted(_ url: URL, root: URL, defaults: UserDefaults) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased(), host.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        for entry in trustedHosts(root: root, defaults: defaults) {
            if entry.hasPrefix("*.") { if host.hasSuffix(String(entry.dropFirst(1))) { return true } }
            else if host == entry { return true }
        }
        return false
    }
}
