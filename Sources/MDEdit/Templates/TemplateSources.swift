import Foundation

/// Where a render gets its folder listings and note sections from. A test supplies a stub (for example one that sleeps).
protocol TemplateSource {
    /// The items of a folder. `error` is empty when it worked; otherwise the reason (`not available`).
    func list(_ folder: String, sort: FilesSort, reverse: Bool, limit: Int?, budget: Budget) throws -> (items: [Value], error: String)
    /// The text under a heading in a note. `error` is empty when it worked; a missing heading gives empty text and no error.
    func section(_ path: String, _ heading: String, budget: Budget) throws -> (text: String, error: String)
    /// The meta block of a note (the `key: value` lines between `---` lines at its top) as a record; empty when there is none.
    func meta(_ path: String, budget: Budget) throws -> (meta: Value, error: String)
}

/// The disk source: the only code in `Templates/` that reads files, and it only reads. Every path goes through `SafePath`.
final class TemplateSources: TemplateSource {
    let root: URL
    private struct Entry { let node: BinderNode, path: String, modified: Date, size: Int }
    private enum Read { case text(String), failed(String) }
    private var listings: [String: [Entry]] = [:]
    private var reads: [String: Read] = [:]
    private var heads: [String: Read] = [:]

    init(root: URL) { self.root = root }

    // MARK: listing

    func list(_ folder: String, sort: FilesSort, reverse: Bool, limit: Int?, budget: Budget) throws -> (items: [Value], error: String) {
        try budget.checkNow()
        let folderURL: URL
        switch SafePath.resolve(folder, in: root, kind: .folder) {
        case .success(let u): folderURL = u
        case .failure: try budget.charge(); return ([], "not available")
        }
        let key = folderURL.path
        var entries: [Entry]
        if let cached = listings[key] {
            entries = cached
        } else {
            let (nodes, raw) = BinderNode.entries(of: folderURL)
            budget.entriesRead += raw
            if budget.entriesRead > budget.limits.entries {
                throw TemplateError.limit("The folders hold more than \(budget.limits.entries) entries.", line: nil)
            }
            let base = SafePath.relative(folderURL, in: root) ?? ""
            entries = []
            for node in nodes where node.isFolder || node.isDocument {
                let rel = base.isEmpty ? node.url.lastPathComponent : base + "/" + node.url.lastPathComponent
                // each child is checked again: a link inside the folder may lead out of it, or to a hidden file
                guard case .success(let resolved) = SafePath.resolve(rel, in: root, kind: node.isFolder ? .folder : .note) else { continue }
                let v = try? resolved.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                entries.append(Entry(node: node, path: rel, modified: v?.contentModificationDate ?? .distantPast, size: node.isFolder ? 0 : (v?.fileSize ?? 0)))
            }
            listings[key] = entries
        }
        try budget.charge(entries.count + 1)
        if sort == .modified {
            // ascending by the full time, equal times in name order (the sort is stable)
            let order = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.path, $0) })
            entries.sort { $0.modified != $1.modified ? $0.modified < $1.modified : order[$0.path]! < order[$1.path]! }
        }
        if reverse { entries.reverse() }
        let cap = min(limit.map { max(0, $0) } ?? budget.limits.listItems, budget.limits.listItems)
        entries = Array(entries.prefix(cap))
        var items: [Value] = []
        for e in entries { items.append(try item(e, budget: budget)) }
        return (items, "")
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func item(_ e: Entry, budget: Budget) throws -> Value {
        let name = e.node.url.lastPathComponent
        let title = e.node.isFolder ? name : try noteTitle(e, budget: budget)
        return .record([
            "name": .text(name), "path": .text(e.path), "kind": .text(e.node.isFolder ? "folder" : "note"),
            "title": .text(title), "modified": .text(Self.dayFormat.string(from: e.modified)), "size": .number(e.size),
        ])
    }

    /// The first heading of a note, from its first bytes; the file name without extension when there is none or it cannot be read.
    private func noteTitle(_ e: Entry, budget: Budget) throws -> String {
        let fallback = e.node.url.deletingPathExtension().lastPathComponent
        let n = budget.limits.titleBytes
        guard budget.bytesRead + n <= budget.limits.readBytes else { return fallback }
        guard let h = try? FileHandle(forReadingFrom: e.node.url) else { return fallback }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: n) else { return fallback }
        budget.bytesRead += data.count
        try budget.charge(1 + data.count / 256)
        let text = TextCut.decode(data)
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

    // MARK: sections

    func section(_ path: String, _ heading: String, budget: Budget) throws -> (text: String, error: String) {
        try budget.checkNow()
        let url: URL
        switch SafePath.resolve(path, in: root, kind: .note) {
        case .success(let u): url = u
        case .failure: try budget.charge(); return ("", "not available")
        }
        let read: Read
        if let cached = reads[url.path] {
            read = cached
        } else {
            read = try load(url, budget: budget)
            reads[url.path] = read
        }
        try budget.charge()
        switch read {
        case .failed(let why): return ("", why)
        case .text(let text):
            return (Self.sectionText(text, heading: heading), "")
        }
    }

    private func load(_ url: URL, budget: Budget) throws -> Read {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size > budget.limits.sectionBytes { return .failed("too large") }
        if budget.bytesRead + size > budget.limits.readBytes { return .failed("read budget used") }
        guard let data = try? Data(contentsOf: url) else { return .failed("unreadable") }
        budget.bytesRead += data.count
        try budget.charge(1 + data.count / 256)
        if data.count > budget.limits.sectionBytes { return .failed("too large") }
        guard let text = String(data: data, encoding: .utf8) else { return .failed("not text") }
        return .text(text)
    }

    // MARK: meta

    func meta(_ path: String, budget: Budget) throws -> (meta: Value, error: String) {
        try budget.checkNow()
        let url: URL
        switch SafePath.resolve(path, in: root, kind: .note) {
        case .success(let u): url = u
        case .failure: try budget.charge(); return (.record([:]), "not available")
        }
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
}
