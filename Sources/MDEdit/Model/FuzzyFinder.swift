import Foundation

/// Every file below the opened folder, ready to be matched against what the person types in "Go to File".
///
/// Speed comes from three things: paths are lowercased once into scalar arrays, so a match is a plain scan with no string
/// work; a query that only extends the last one looks at the files the last one matched; and only the best `limit` results
/// are kept while scanning, never a sorted list of everything.
final class FileIndex {
    struct Entry {
        let url: URL
        /// Path below the opened folder, as shown.
        let path: String
        /// The same, lowercased, as unicode scalars.
        let lower: [UInt32]
        /// Where the file name starts in `lower`.
        let nameStart: Int
    }

    struct Hit: Equatable {
        let entry: Int
        let score: Int
    }

    private(set) var entries: [Entry] = []
    private var lastQuery: [[UInt32]] = []
    private var lastMatches: [Int] = []

    /// Reads the files of a scanned tree. Folders are not entries; hidden files are already left out of the tree.
    init(root: BinderNode, rootURL: URL) {
        let base = rootURL.standardizedFileURL.path
        var out: [Entry] = []
        func walk(_ n: BinderNode) {
            for c in n.children {
                if c.isFolder { walk(c); continue }
                let p = c.url.standardizedFileURL.path
                let rel = p.hasPrefix(base + "/") ? String(p.dropFirst(base.count + 1)) : c.url.lastPathComponent
                let lower = Self.fold(rel)
                let start = (lower.lastIndex(of: 47).map { $0 + 1 }) ?? 0
                out.append(Entry(url: c.url, path: rel, lower: lower, nameStart: start))
            }
        }
        walk(root)
        entries = out
    }

    init(paths: [String]) {
        entries = paths.map { p in
            let lower = Self.fold(p)
            return Entry(url: URL(fileURLWithPath: "/" + p), path: p, lower: lower, nameStart: (lower.lastIndex(of: 47).map { $0 + 1 }) ?? 0)
        }
    }

    // MARK: matching

    /// The best `limit` files for `query`, best first. Words are separated by spaces and every word must match, in any order.
    func search(_ query: String, limit: Int = 50) -> [Hit] {
        let terms = Self.terms(query)
        if terms.isEmpty { lastQuery = []; lastMatches = []; return [] }
        // an extended query can only match what the shorter one matched
        let pool: [Int]?
        if !lastQuery.isEmpty, lastQuery.count <= terms.count,
           zip(lastQuery, terms).enumerated().allSatisfy({ i, p in i == lastQuery.count - 1 ? Self.hasPrefix(p.1, p.0) : p.0 == p.1 }) {
            pool = lastMatches
        } else { pool = nil }

        var best: [Hit] = []
        best.reserveCapacity(limit + 1)
        var matches: [Int] = []
        func consider(_ i: Int) {
            guard let s = Self.score(terms, entries[i]) else { return }
            matches.append(i)
            let hit = Hit(entry: i, score: s)
            if best.count == limit, !better(hit, best[limit - 1]) { return }
            // insertion into the short sorted list
            var at = best.count
            while at > 0, better(hit, best[at - 1]) { at -= 1 }
            best.insert(hit, at: at)
            if best.count > limit { best.removeLast() }
        }
        if let pool { for i in pool { consider(i) } } else { for i in entries.indices { consider(i) } }
        lastQuery = terms
        lastMatches = matches
        return best
    }

    private func better(_ a: Hit, _ b: Hit) -> Bool {
        if a.score != b.score { return a.score > b.score }
        let x = entries[a.entry], y = entries[b.entry]
        if x.lower.count != y.lower.count { return x.lower.count < y.lower.count }
        return x.path < y.path
    }

    func forget() { lastQuery = []; lastMatches = [] }

    /// Positions (in scalars of the path) that `query` matched in `entry`, for highlighting.
    func positions(_ query: String, in entry: Entry) -> [Int] {
        var out: [Int] = []
        for t in Self.terms(query) { out += Self.match(t, in: entry)?.positions ?? [] }
        return Array(Set(out)).sorted()
    }

    // MARK: scoring

    static func terms(_ query: String) -> [[UInt32]] {
        query.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { fold(String($0)) }
    }

    private static func hasPrefix(_ a: [UInt32], _ p: [UInt32]) -> Bool { a.count >= p.count && a[..<p.count].elementsEqual(p) }

    /// Lowercase, one scalar at a time. A scalar whose lowercase is longer keeps its own form.
    static func fold(_ s: String) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(s.unicodeScalars.count)
        for u in s.unicodeScalars {
            if u.value < 128 { out.append(u.value >= 65 && u.value <= 90 ? u.value + 32 : u.value); continue }
            let l = String(u).lowercased().unicodeScalars
            out.append(l.count == 1 ? l.first!.value : u.value)
        }
        return out
    }

    private static func score(_ terms: [[UInt32]], _ e: Entry) -> Int? {
        var total = 0
        for t in terms {
            guard let m = match(t, in: e) else { return nil }
            total += m.score
        }
        // shorter paths first when all else is equal
        return total - e.lower.count / 8
    }

    /// One word against one path. A word matches in one of two ways, and never by letters picked out of the whole path:
    /// 1. its letters appear in order inside the file name (`mtg` finds `Meeting.md`), or
    /// 2. it appears as written, in one piece, anywhere in the path (`goals` finds everything in a `goals` folder).
    /// The first scores higher: letters in a row, letters after a separator, and a name that starts with the word or is it.
    static func match(_ t: [UInt32], in e: Entry) -> (score: Int, positions: [Int])? {
        let c = e.lower
        let n = c.count, m = t.count, s = e.nameStart
        guard m > 0, m <= n else { return nil }
        // 1. in order inside the file name
        var j = 0, i = s
        while i < n, j < m { if c[i] == t[j] { j += 1 }; i += 1 }
        if j == m {
            // walk back from the end of that match to the tightest start
            var end = i - 1
            var pos = [Int](repeating: 0, count: m)
            var k = m - 1
            while k >= 0 {
                if c[end] == t[k] { pos[k] = end; k -= 1 }
                end -= 1
            }
            // letters spread thinly over a long name are not a match either
            if pos[m - 1] - pos[0] + 1 <= max(m * 3, m + 6) { return scoreName(pos, e) }
        }
        return substringMatch(t, e)
    }

    private static func scoreName(_ pos: [Int], _ e: Entry) -> (score: Int, positions: [Int]) {
        let c = e.lower, s = e.nameStart, m = pos.count
        let t = pos.map { c[$0] }
        do {
            var score = 0, prev = -2
            for (idx, p) in pos.enumerated() {
                score += 16 + 6
                if p == prev + 1 { score += 14 }
                else if idx > 0 { score -= min(8, 3 + (p - prev - 2) / 2) }
                if p == s || isSeparator(c[p - 1]) { score += 14 }
                prev = p
            }
            // the word is the file name, or the start of it, or the name without its extension
            let name = c[s...]
            if name.elementsEqual(t) { score += 80 }
            else if name.count >= m, name[name.startIndex..<name.startIndex + m].elementsEqual(t) { score += 40 }
            else if let dot = name.lastIndex(of: 46), c[s..<dot].elementsEqual(t) { score += 70 }
            return (score, pos)
        }
    }

    /// The word in one piece somewhere in the path (a folder name).
    private static func substringMatch(_ t: [UInt32], _ e: Entry) -> (score: Int, positions: [Int])? {
        let c = e.lower, n = c.count, m = t.count
        var best: Int?
        var at = 0
        while at + m <= n {
            if c[at] == t[0], c[at..<at + m].elementsEqual(t) {
                if best == nil { best = at }
                if at == 0 || isSeparator(c[at - 1]) { best = at; break }
            }
            at += 1
        }
        guard let start = best else { return nil }
        var score = 16 * m + 14 * (m - 1) - 20
        if start == 0 || isSeparator(c[start - 1]) { score += 10 }
        return (score, Array(start..<start + m))
    }

    private static func isSeparator(_ u: UInt32) -> Bool { u == 47 || u == 45 || u == 95 || u == 46 || u == 32 }
}
