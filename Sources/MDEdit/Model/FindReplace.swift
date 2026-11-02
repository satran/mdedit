import Foundation

struct FindOptions: Equatable {
    var matchCase = false
    var wholeWord = false
    var regex = false
    var preserveCase = false
}

/// One hit: where it is (UTF-16, as the text view counts), its 1-based line, and the line around it for the result list.
struct FindMatch: Equatable, Identifiable {
    let range: NSRange
    let line: Int
    let before: String
    let text: String
    let after: String
    let replacement: String
    var id: Int { range.location }
}

/// Searching and replacing in text. Pure functions: the panel, the editor and the folder replace all go through here.
enum FindEngine {
    static let maxMatchesPerFile = 5_000
    static let maxMatchesTotal = 20_000
    /// A pattern that backtracks without end must not freeze the app: the search stops and says it was cut short.
    static let timeLimit: TimeInterval = 2

    struct Compiled {
        let regex: NSRegularExpression
        let template: String
        let options: FindOptions
    }

    /// nil for an empty query; throws the regex error text for a pattern that does not compile.
    static func compile(_ query: String, replacement: String, options: FindOptions) throws -> Compiled? {
        guard !query.isEmpty else { return nil }
        var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = "(?<![\\p{L}\\p{N}_])(?:\(pattern))(?![\\p{L}\\p{N}_])" }
        var flags: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.matchCase { flags.insert(.caseInsensitive) }
        do { return Compiled(regex: try NSRegularExpression(pattern: pattern, options: flags), template: replacement, options: options) }
        catch { throw FindError.invalid(options.regex ? "Not a valid pattern" : "Cannot search for that") }
    }

    enum FindError: Error, Equatable { case invalid(String) }

    struct Result {
        var matches: [FindMatch] = []
        /// Stopped at a limit or the time limit: there are more than shown.
        var truncated = false
    }

    static func search(_ text: String, _ c: Compiled, limit: Int = maxMatchesPerFile, deadline: Date? = nil) -> Result {
        let ns = text as NSString
        var out = Result()
        var line = 1, counted = 0
        let deadline = deadline ?? Date().addingTimeInterval(timeLimit)
        c.regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: ns.length)) { result, _, stop in
            if Date() > deadline { out.truncated = true; stop.pointee = true; return }
            guard let r = result, r.range.length > 0 else { return }
            if out.matches.count >= limit { out.truncated = true; stop.pointee = true; return }
            line += newlines(in: ns, from: counted, to: r.range.location)
            counted = r.range.location
            let rep = replacement(for: r, in: ns, c)
            out.matches.append(context(of: r.range, line: line, in: ns, replacement: rep))
        }
        return out
    }

    /// What the match becomes: the template (with $1 groups in regex mode), in the case of the matched text when asked.
    static func replacement(for r: NSTextCheckingResult, in text: NSString, _ c: Compiled) -> String {
        let raw = c.options.regex ? c.regex.replacementString(for: r, in: text as String, offset: 0, template: c.template) : c.template
        return c.options.preserveCase ? recase(raw, like: text.substring(with: r.range)) : raw
    }

    /// "time to restore" -> "failed deployment recovery time", "Time to restore" -> "Failed deployment recovery time",
    /// "TIME" -> "FAILED" (only the first letter changes for lower and capitalised, so names in the replacement keep their
    /// capitals). Mixed case is left as typed.
    static func recase(_ replacement: String, like matched: String) -> String {
        let letters = matched.filter { $0.isLetter }
        guard let first = letters.first, !replacement.isEmpty else { return replacement }
        if letters.count > 1, letters.allSatisfy({ $0.isUppercase }) { return replacement.uppercased() }
        if letters.allSatisfy({ $0.isLowercase }) { return replacement.prefix(1).lowercased() + replacement.dropFirst() }
        if first.isUppercase, letters.dropFirst().allSatisfy({ $0.isLowercase }) { return replacement.prefix(1).uppercased() + replacement.dropFirst() }
        return replacement
    }

    /// Replaces the matches whose start is in `only` (all when nil). `nil` back means the text no longer holds a match for
    /// every wanted position: it changed since the search.
    static func replace(in text: String, _ c: Compiled, only: Set<Int>? = nil) -> (text: String, count: Int)? {
        let ns = text as NSString
        var out = "", last = 0, count = 0, seen = Set<Int>()
        let deadline = Date().addingTimeInterval(timeLimit * 4)
        var timedOut = false
        c.regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: ns.length)) { result, _, stop in
            if Date() > deadline { timedOut = true; stop.pointee = true; return }
            guard let r = result, r.range.length > 0, only == nil || only!.contains(r.range.location) else { return }
            out += ns.substring(with: NSRange(location: last, length: r.range.location - last))
            out += replacement(for: r, in: ns, c)
            last = r.range.location + r.range.length
            seen.insert(r.range.location); count += 1
        }
        if timedOut { return nil }
        if let only, !only.isSubset(of: seen) { return nil }
        out += ns.substring(from: last)
        return (out, count)
    }

    // MARK: pieces

    private static func newlines(in ns: NSString, from: Int, to: Int) -> Int {
        var n = 0, i = from
        while i < to { if ns.character(at: i) == 10 { n += 1 }; i += 1 }
        return n
    }

    /// The line the match is on, cut to a window of a few words either side. A match inside a very long line (minified
    /// text, a pasted blob) still gives a short row.
    static func context(of range: NSRange, line: Int, in ns: NSString, replacement: String) -> FindMatch {
        let para = ns.lineRange(for: NSRange(location: range.location, length: 0))
        let lineEnd = para.location + para.length
        var start = max(para.location, range.location - 36)
        var end = min(lineEnd, range.location + range.length + 48)
        if start > para.location { start = ns.rangeOfComposedCharacterSequence(at: start).location }
        if end < lineEnd, end > 0 { end = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: end - 1)) }
        let clip = { (r: NSRange) in ns.substring(with: r).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: "") }
        var before = clip(NSRange(location: start, length: range.location - start))
        var after = clip(NSRange(location: NSMaxRange(range), length: max(0, end - NSMaxRange(range))))
        // only the outer edges are trimmed: the spaces next to the match are part of the sentence
        if start == para.location { before = String(before.drop { $0 == " " || $0 == "\t" }) } else { before = "…" + before }
        if end >= lineEnd { while let l = after.last, l == " " || l == "\t" { after.removeLast() } } else { after += "…" }
        let shown = range.length > 200 ? NSRange(location: range.location, length: 200) : range
        return FindMatch(range: range, line: line, before: before, text: clip(shown) + (shown.length < range.length ? "…" : ""), after: after, replacement: replacement)
    }
}

// MARK: folder

/// The matches of one file in the folder search.
struct FileHits: Identifiable, Equatable {
    let url: URL
    let name: String
    /// The folder it is in, relative to the opened folder; empty at the top.
    let folder: String
    var matches: [FindMatch]
    var truncated = false
    var id: URL { url }
}

enum FolderFind {
    /// Notes in `files`, in order, with their matches. Unreadable and oversized files are skipped. Checks `cancelled` between
    /// files so typing another letter ends the old search at once.
    static func search(_ files: [(url: URL, folder: String)], _ c: FindEngine.Compiled, cancelled: () -> Bool = { false }) -> [FileHits] {
        var out: [FileHits] = []
        var total = 0
        for f in files {
            if cancelled() || total >= FindEngine.maxMatchesTotal { break }
            guard let loaded = read(f.url) else { continue }
            let r = FindEngine.search(loaded.text, c, limit: min(FindEngine.maxMatchesPerFile, FindEngine.maxMatchesTotal - total))
            guard !r.matches.isEmpty else { continue }
            total += r.matches.count
            out.append(FileHits(url: f.url, name: f.url.deletingPathExtension().lastPathComponent, folder: f.folder, matches: r.matches, truncated: r.truncated))
        }
        return out
    }

    struct Loaded { let text: String; let encoding: String.Encoding; let bom: Bool; let data: Data }

    static func read(_ url: URL) -> Loaded? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)[.size] as? Int) ?? 0
        guard size <= DocumentStore.maxBytes, let data = try? Data(contentsOf: url), let d = try? DocumentStore.decode(data) else { return nil }
        return Loaded(text: d.text, encoding: d.encoding, bom: d.bom, data: data)
    }

    /// The bytes of `text` in the file's own encoding; nil when that encoding cannot hold it.
    static func encode(_ text: String, like l: Loaded) -> Data? {
        switch l.encoding {
        case .utf8: return (l.bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(text.utf8)
        default: return text.data(using: l.encoding)
        }
    }

    /// What was written, so it can be taken back.
    struct Backup: Equatable { let url: URL; let before: Data; let after: Data }

    struct Report {
        var replaced = 0
        var files = 0
        var backups: [Backup] = []
        var skipped: [String] = []
    }

    /// Replaces the chosen matches (start offsets per file) on disk. A file that changed since the search, or whose
    /// encoding cannot hold the result, is left alone and listed in `skipped`.
    static func replace(_ chosen: [(url: URL, starts: Set<Int>)], _ c: FindEngine.Compiled) -> Report {
        var report = Report()
        for item in chosen where !item.starts.isEmpty {
            let name = item.url.lastPathComponent
            guard let l = read(item.url) else { report.skipped.append("\(name): could not be read"); continue }
            guard let done = FindEngine.replace(in: l.text, c, only: item.starts) else { report.skipped.append("\(name): changed since the search"); continue }
            guard let data = encode(done.text, like: l) else { report.skipped.append("\(name): its encoding cannot hold the new text"); continue }
            do { try DocumentStore.replace(item.url, with: data) } catch { report.skipped.append("\(name): \(error.localizedDescription)"); continue }
            report.replaced += done.count; report.files += 1
            report.backups.append(Backup(url: item.url, before: l.data, after: data))
        }
        return report
    }

    /// Puts files back as they were, each only if it is still as the replace left it. Returns the backups that undo this.
    static func restore(_ backups: [Backup]) -> (done: [Backup], skipped: [String]) {
        var done: [Backup] = [], skipped: [String] = []
        for b in backups {
            guard (try? Data(contentsOf: b.url)) == b.after else { skipped.append("\(b.url.lastPathComponent): changed since the replace"); continue }
            do { try DocumentStore.replace(b.url, with: b.before); done.append(Backup(url: b.url, before: b.after, after: b.before)) }
            catch { skipped.append("\(b.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return (done, skipped)
    }
}
