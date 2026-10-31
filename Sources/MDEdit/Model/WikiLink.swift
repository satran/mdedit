import Foundation

/// Obsidian-style links: [[Note]], [[Note|alias]], [[Note#Heading]], [[folder/Note]].
struct WikiLink: Equatable {
    var target: String      // as written, without alias: "folder/Note#Heading"
    var alias: String?

    /// The note part of the target, without a heading.
    var note: String { String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "").trimmingCharacters(in: .whitespaces) }
    var heading: String? {
        let p = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        return p.count > 1 ? String(p[1]).trimmingCharacters(in: .whitespaces) : nil
    }
    var shown: String { alias ?? target }

    static let regex = try! NSRegularExpression(pattern: "\\[\\[([^\\[\\]\\n|]+)(?:\\|([^\\[\\]\\n]+))?\\]\\]")

    static func parse(_ s: String) -> [(range: Range<String.Index>, link: WikiLink)] {
        let ns = s as NSString
        return regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let r = Range(m.range, in: s) else { return nil }
            let alias = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2))
            return (r, WikiLink(target: ns.substring(with: m.range(at: 1)), alias: alias))
        }
    }

    /// The URL a rendered wiki link carries, so the viewer can tell it from a web link.
    var url: URL? {
        URL(string: "mdedit://wiki/" + (target.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
    }
    static func target(from url: URL) -> String? {
        guard url.scheme == "mdedit", url.host == "wiki" else { return nil }
        return String(url.path.dropFirst()).removingPercentEncoding
    }
}

/// Finds the note a link points at. Built once per scan of the folder, so styling a document does not walk the tree.
final class WikiIndex: @unchecked Sendable {
    private let byName: [String: [URL]]
    /// Note names for completion; a name shared by two notes is shown with its folder.
    let names: [String]

    init(root: BinderNode?) {
        let files = root?.files ?? []
        var d: [String: [URL]] = [:]
        for f in files { d[f.name.lowercased(), default: []].append(f.url) }
        byName = d
        let rootParts = root?.url.standardizedFileURL.pathComponents.count ?? 0
        names = files.map { f in
            if (d[f.name.lowercased()]?.count ?? 0) > 1 {
                return f.url.standardizedFileURL.deletingPathExtension().pathComponents.dropFirst(rootParts).joined(separator: "/")
            }
            return f.name
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// "Note" matches any file named Note.md (case-insensitive), the one nearest `from` first; "folder/Note" must match the path's end.
    func resolve(_ link: WikiLink, from current: URL?) -> URL? {
        let wanted = link.note.lowercased().split(separator: "/").map(String.init)
        guard let last = wanted.last, let all = byName[last] else { return nil }
        let candidates = all.filter { u in
            let parts = u.deletingPathExtension().pathComponents.map { $0.lowercased() }
            return parts.count >= wanted.count && Array(parts.suffix(wanted.count)) == wanted
        }
        guard !candidates.isEmpty else { return nil }
        let here = current?.deletingLastPathComponent().pathComponents ?? []
        func score(_ u: URL) -> (Int, Int) {
            let dir = u.deletingLastPathComponent().pathComponents
            let common = zip(dir, here).prefix { $0 == $1 }.count
            return (-common, dir.count)       // most shared folders, then shallowest
        }
        return candidates.min { score($0) < score($1) }
    }

    static func resolve(_ link: WikiLink, from current: URL?, in root: BinderNode?) -> URL? {
        WikiIndex(root: root).resolve(link, from: current)
    }
}
