import Foundation

struct FilesOptions {
    var sort = FilesSort.name
    var reverse = false
    var limit: Int?
    var recursive = false
    /// Also list `.html` and `.htm` files, as kind `page`.
    var pages = false
    /// A pattern for the file name (`*` and `?`).
    var match: String?
}

/// Where a render gets its folder listings and notes from. A test supplies a stub (for example one that sleeps).
/// Every method reports a read that cannot be done as an empty result plus a short reason, and throws only for the hard limits.
protocol TemplateSource {
    /// The items of a folder. `error` is empty when it worked; otherwise the reason (`not available`).
    func list(_ folder: String, options: FilesOptions, budget: Budget) throws -> (items: [Value], error: String)
    /// The text under a heading in a note. A missing heading gives empty text and no error.
    func section(_ path: String, _ heading: String, budget: Budget) throws -> (text: String, error: String)
    /// The meta block of a note (the `key: value` lines between `---` lines at its top) as a record; empty when there is none.
    func meta(_ path: String, budget: Budget) throws -> (meta: Value, error: String)
    /// The task lines of a note, one record each (see `TemplateTasks`).
    func tasks(_ path: String, budget: Budget) throws -> (items: [Value], error: String)
    /// A JSON or YAML file as a value.
    func data(_ path: String, budget: Budget) throws -> (meta: Value, error: String)
    /// The text of an HTML page to include.
    func include(_ path: String, budget: Budget) throws -> (text: String, error: String)
    /// The path (relative to the opened folder) of the note a wiki link name stands for, or nil.
    func wikiTarget(_ name: String, budget: Budget) throws -> String?
}

/// The disk source: the only code in `Templates/` that reads files, and it only reads. Every path goes through `SafePath`.
final class TemplateSources: TemplateSource {
    let root: URL
    private struct Entry { let url: URL, isFolder: Bool, isPage: Bool, path: String, modified: Date, size: Int }
    private enum Read { case text(String), failed(String) }
    private var listings: [String: [Entry]] = [:]
    private var reads: [String: Read] = [:]
    private var heads: [String: Read] = [:]
    private var wikiIndex: WikiIndex?

    init(root: URL) { self.root = root }

    // MARK: listing

    func list(_ folder: String, options o: FilesOptions, budget: Budget) throws -> (items: [Value], error: String) {
        try budget.checkNow()
        let folderURL: URL
        switch SafePath.resolve(folder, in: root, kind: .folder) {
        case .success(let u): folderURL = u
        case .failure: try budget.charge(); return ([], "not available")
        }
        let key = "\(folderURL.path)|\(o.recursive)|\(o.pages)"
        var entries: [Entry]
        if let cached = listings[key] {
            entries = cached
        } else {
            entries = try collect(folderURL, recursive: o.recursive, pages: o.pages, budget: budget)
            listings[key] = entries
        }
        try budget.charge(entries.count + 1)
        if let pattern = o.match { entries = entries.filter { TemplateGlob.matches(pattern, $0.url.lastPathComponent) } }
        if o.sort == .modified {
            // ascending by the full time, equal times in name order (the sort is stable)
            let order = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.path, $0) })
            entries.sort { $0.modified != $1.modified ? $0.modified < $1.modified : order[$0.path]! < order[$1.path]! }
        } else if o.recursive {
            // folders are not listed when recursive, so the order is by path
            entries.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        if o.reverse { entries.reverse() }
        let cap = min(o.limit.map { max(0, $0) } ?? budget.limits.listItems, budget.limits.listItems)
        entries = Array(entries.prefix(cap))
        var items: [Value] = []
        for e in entries { items.append(try item(e, budget: budget)) }
        return (items, "")
    }

    /// The notes (and pages) of a folder; its subfolders too when not recursive; every level below it when recursive.
    private func collect(_ folder: URL, recursive: Bool, pages: Bool, budget: Budget) throws -> [Entry] {
        var out: [Entry] = []
        var queue: [(URL, Int)] = [(folder, 0)]
        while !queue.isEmpty {
            let (dir, depth) = queue.removeFirst()
            try budget.checkNow()
            let (nodes, raw) = BinderNode.entries(of: dir)
            budget.entriesRead += raw
            if budget.entriesRead > budget.limits.entries {
                throw TemplateError.limit("The folders hold more than \(budget.limits.entries) entries.", line: nil)
            }
            let base = SafePath.relative(dir, in: root) ?? ""
            for node in nodes {
                let isPage = !node.isFolder && node.isHTML
                guard node.isFolder || node.isDocument || (pages && isPage) else { continue }
                let rel = base.isEmpty ? node.url.lastPathComponent : base + "/" + node.url.lastPathComponent
                // each child is checked again: a link inside the folder may lead out of it, or to a hidden file
                let kind: SafePath.Kind = node.isFolder ? .folder : (isPage ? .page : .note)
                guard case .success(let resolved) = SafePath.resolve(rel, in: root, kind: kind) else { continue }
                if node.isFolder {
                    if recursive { if depth + 1 < budget.limits.recursiveDepth { queue.append((resolved, depth + 1)) } }
                    else { out.append(entry(node, rel, resolved, isPage: false)) }
                } else {
                    out.append(entry(node, rel, resolved, isPage: isPage))
                }
            }
        }
        return out
    }

    private func entry(_ node: BinderNode, _ rel: String, _ resolved: URL, isPage: Bool) -> Entry {
        let v = try? resolved.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return Entry(url: node.url, isFolder: node.isFolder, isPage: isPage, path: rel, modified: v?.contentModificationDate ?? .distantPast, size: node.isFolder ? 0 : (v?.fileSize ?? 0))
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func item(_ e: Entry, budget: Budget) throws -> Value {
        let name = e.url.lastPathComponent
        let title = e.isFolder ? name : try noteTitle(e, budget: budget)
        let folder = e.path.contains("/") ? String(e.path[..<e.path.lastIndex(of: "/")!]) : ""
        return .record([
            "name": .text(name), "path": .text(e.path), "folder": .text(folder), "ext": .text(e.url.pathExtension.lowercased()),
            "kind": .text(e.isFolder ? "folder" : (e.isPage ? "page" : "note")),
            "title": .text(title), "modified": .text(Self.dayFormat.string(from: e.modified)), "size": .number(e.size),
        ])
    }

    private static let pageTitle = try! NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])

    /// The first heading of a note (the `<title>` of a page), from its first bytes; the file name without extension when there is none.
    private func noteTitle(_ e: Entry, budget: Budget) throws -> String {
        let fallback = e.url.deletingPathExtension().lastPathComponent
        let n = budget.limits.titleBytes
        guard budget.bytesRead + n <= budget.limits.readBytes else { return fallback }
        guard let h = try? FileHandle(forReadingFrom: e.url) else { return fallback }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: n) else { return fallback }
        budget.bytesRead += data.count
        try budget.charge(1 + data.count / 256)
        let text = TextCut.decode(data)
        if e.isPage {
            let ns = text as NSString
            if let m = Self.pageTitle.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                let t = ns.substring(with: m.range(at: 1)).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                if !t.isEmpty { return t }
            }
            return fallback
        }
        if let first = Outline.headings(in: text).first {
            let t = Self.cleanTitle(first.title)
            if !t.isEmpty { return t }
        }
        return fallback
    }

    /// A heading's title without closing `#` marks (`## Summary ##` is "Summary").
    static func cleanTitle(_ t: String) -> String {
        var s = Substring(t)
        while s.last == " " { s = s.dropLast() }
        if s.last == "#" {
            var u = s
            while u.last == "#" { u = u.dropLast() }
            if u.isEmpty || u.last == " " { s = u }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: whole-file reads

    private func resolve(_ path: String, _ kind: SafePath.Kind, budget: Budget) throws -> URL? {
        try budget.checkNow()
        switch SafePath.resolve(path, in: root, kind: kind) {
        case .success(let u): return u
        case .failure: try budget.charge(); return nil
        }
    }

    /// The whole file as text, up to `cap` bytes; cached for the render (a hit costs steps but no bytes).
    private func text(_ url: URL, cap: Int, budget: Budget) throws -> Read {
        let key = "\(cap)|\(url.path)"
        if let cached = reads[key] { return cached }
        let r = try load(url, cap: cap, budget: budget)
        reads[key] = r
        return r
    }

    private func load(_ url: URL, cap: Int, budget: Budget) throws -> Read {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size > cap { return .failed("too large") }
        if budget.bytesRead + size > budget.limits.readBytes { return .failed("read budget used") }
        guard let data = try? Data(contentsOf: url) else { return .failed("unreadable") }
        budget.bytesRead += data.count
        try budget.charge(1 + data.count / 256)
        if data.count > cap { return .failed("too large") }
        guard let text = String(data: data, encoding: .utf8) else { return .failed("not text") }
        return .text(text)
    }

    // MARK: sections

    func section(_ path: String, _ heading: String, budget: Budget) throws -> (text: String, error: String) {
        guard let url = try resolve(path, .note, budget: budget) else { return ("", "not available") }
        let read = try text(url, cap: budget.limits.sectionBytes, budget: budget)
        try budget.charge()
        switch read {
        case .failed(let why): return ("", why)
        case .text(let text): return (Self.sectionText(text, heading: heading), "")
        }
    }

    /// From the line after the first heading whose title matches, up to the next heading of the same or a higher level.
    static func sectionText(_ text: String, heading: String) -> String {
        let want = heading.trimmingCharacters(in: .whitespaces)
        let heads = Outline.headings(in: text)
        guard let i = heads.firstIndex(where: { cleanTitle($0.title) == want }) else { return "" }
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: heads[i].location, length: 0))
        let start = line.location + line.length
        let end = heads[(i + 1)...].first(where: { $0.level <= heads[i].level })?.location ?? ns.length
        guard end > start else { return "" }
        return ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: meta

    func meta(_ path: String, budget: Budget) throws -> (meta: Value, error: String) {
        guard let url = try resolve(path, .note, budget: budget) else { return (.record([:]), "not available") }
        let read: Read
        if let cached = heads[url.path] { read = cached } else { read = try loadHead(url, budget: budget); heads[url.path] = read }
        try budget.charge()
        switch read {
        case .failed(let why): return (.record([:]), why)
        case .text(let text): return (Self.metaRecord(text), "")
        }
    }

    /// Only the top of the note is read: the meta block is at the top, and a long note does not make its meta unreadable.
    private func loadHead(_ url: URL, budget: Budget) throws -> Read {
        let n = budget.limits.metaBytes
        if budget.bytesRead + n > budget.limits.readBytes { return .failed("read budget used") }
        guard let h = try? FileHandle(forReadingFrom: url) else { return .failed("unreadable") }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: n) else { return .failed("unreadable") }
        budget.bytesRead += data.count
        try budget.charge(1 + data.count / 256)
        if data.contains(0) { return .failed("not text") }
        return .text(TextCut.decode(data))
    }

    /// A `true` is the text "true" and a `false` is empty, so `{% if m.draft %}` works.
    static func metaRecord(_ text: String) -> Value {
        guard let fm = FrontMatter.parse(text) else { return .record([:]) }
        var record: [String: Value] = [:]
        for p in fm.properties {
            switch p.value {
            case .text(let t): record[p.key] = .text(t)
            case .bool(let b): record[p.key] = b ? .text("true") : .empty
            case .list(let l): record[p.key] = .list(l.map { .text($0) })
            }
        }
        return .record(record)
    }

    // MARK: tasks, data, include

    func tasks(_ path: String, budget: Budget) throws -> (items: [Value], error: String) {
        guard let url = try resolve(path, .note, budget: budget) else { return ([], "not available") }
        let read = try text(url, cap: budget.limits.taskBytes, budget: budget)
        try budget.charge()
        switch read {
        case .failed(let why): return ([], why)
        case .text(let text):
            let items = TemplateTasks.parse(text, maxItems: budget.limits.taskItems)
            try budget.charge(items.count)
            return (items, "")
        }
    }

    func data(_ path: String, budget: Budget) throws -> (meta: Value, error: String) {
        guard let url = try resolve(path, .data, budget: budget) else { return (.empty, "not available") }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size > budget.limits.dataBytes { return (.empty, "too large") }
        if budget.bytesRead + size > budget.limits.readBytes { return (.empty, "read budget used") }
        guard let bytes = try? Data(contentsOf: url) else { return (.empty, "unreadable") }
        budget.bytesRead += bytes.count
        try budget.charge(1 + bytes.count / 256)
        if bytes.count > budget.limits.dataBytes { return (.empty, "too large") }
        do {
            let isYAML = ["yaml", "yml"].contains(url.pathExtension.lowercased())
            let v = try TemplateData.parse(bytes, isYAML: isYAML, limits: budget.limits)
            try budget.charge(bytes.count / 256)
            return (v, "")
        } catch TemplateData.Failure.tooLarge { return (.empty, "too large") }
        catch { return (.empty, "not text") }
    }

    func include(_ path: String, budget: Budget) throws -> (text: String, error: String) {
        guard let url = try resolve(path, .page, budget: budget) else { return ("", "not available") }
        let read = try text(url, cap: budget.limits.templateBytes, budget: budget)
        switch read {
        case .failed(let why): return ("", why)
        case .text(let text): return (text, "")
        }
    }

    // MARK: wiki links

    func wikiTarget(_ name: String, budget: Budget) throws -> String? {
        if wikiIndex == nil {
            try budget.checkNow()
            let tree = BinderNode.scan(root)
            let count = tree.files.count
            budget.entriesRead += count
            if budget.entriesRead > budget.limits.entries { throw TemplateError.limit("The folders hold more than \(budget.limits.entries) entries.", line: nil) }
            try budget.charge(count / 16 + 1)
            wikiIndex = WikiIndex(root: tree)
        }
        guard let url = wikiIndex?.resolve(WikiLink(target: name, alias: nil), from: nil), let rel = SafePath.relative(url, in: root),
              case .success = SafePath.resolve(rel, in: root, kind: .note) else { return nil }
        return rel
    }
}
