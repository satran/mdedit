import Foundation

/// Notes can come from anywhere. A few thousand nested quotes or list levels would overflow the stack of the
/// recursive code that draws and exports Markdown, so nesting is capped before any of it runs.
enum MarkdownLimits {
    /// Block quotes and list levels deeper than this are flattened.
    static let maxQuoteDepth = 24
    static let maxIndent = 48
    /// Longest line (in UTF-16 units) handed to the Markdown parser; the rest of a longer line is cut off.
    static let maxLine = 200_000

    /// The text with nesting capped. Ordinary notes come back unchanged (and without copying).
    static func clamp(_ source: String) -> String {
        guard needsClamp(source) else { return source }
        var out: [Substring] = []
        var changed = false
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let fixed = clampLine(line)
            if fixed.count != line.count { changed = true }
            out.append(fixed)
        }
        return changed ? out.joined(separator: "\n") : source
    }

    private static func needsClamp(_ s: String) -> Bool {
        var quotes = 0, indent = 0, atStart = true, run = 0
        for b in s.utf8 {
            run += 1
            if b == 10 { quotes = 0; indent = 0; atStart = true; run = 0; continue }
            if run > maxLine { return true }
            guard atStart else { continue }
            switch b {
            case UInt8(ascii: ">"): quotes += 1; if quotes > maxQuoteDepth { return true }
            case UInt8(ascii: " "), UInt8(ascii: "\t"): indent += 1; if indent > maxIndent + maxQuoteDepth { return true }
            default: atStart = false
            }
        }
        return false
    }

    private static func clampLine(_ line: Substring) -> Substring {
        var line = line
        if line.utf16.count > maxLine { line = line.prefix(maxLine) }
        let u = line.utf8
        // leading ">" markers (with spaces between them): keep the first maxQuoteDepth, drop the rest
        var i = u.startIndex, quotes = 0
        while i < u.endIndex {
            let b = u[i]
            if b == 62 { quotes += 1; if quotes == maxQuoteDepth { i = u.index(after: i); break } }
            else if b != 32 && b != 9 { break }
            i = u.index(after: i)
        }
        if quotes == maxQuoteDepth {
            var rest = i
            while rest < u.endIndex, u[rest] == 62 || u[rest] == 32 || u[rest] == 9 { rest = u.index(after: rest) }
            line = Substring(String(line[line.startIndex..<i]) + " " + String(line[rest...]))
        }
        // leading indentation, capped
        let v = line.utf8
        var start = v.startIndex, spaces = 0
        while start < v.endIndex, v[start] == 32 || v[start] == 9 { start = v.index(after: start); spaces += 1 }
        if spaces > maxIndent { line = Substring(String(repeating: " ", count: maxIndent) + String(line[start...])) }
        return line
    }
}
