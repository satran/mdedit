import Foundation
import Markdown

/// The `markdown` filter: text to safe HTML, with two extras. `[[Note]]` and `[[Note|alias]]` become links to the note's file (when it
/// exists), and with a `base` folder a relative link or picture is made relative to that folder instead of the opened folder.
enum TemplateMarkdown {
    private static let wikiScheme = "mdedit-wiki:"

    /// `wiki` returns the path (relative to the opened folder) of the note a name stands for, or nil.
    static func render(_ text: String, base: String?, wiki: (String) -> String?) -> String {
        let prepared = linkWiki(text, wiki: wiki)
        let document = Document(parsing: MarkdownLimits.clamp(prepared), options: [.disableSmartOpts])
        var rebase = Rebase(base: base)
        let rewritten = rebase.visit(document) as? Document ?? document
        return SafeHTML.render(rewritten, preview: false)
    }

    // MARK: wiki links

    /// Replaces wiki links outside code spans and fenced blocks with Markdown links to a marked target, or with their plain text.
    static func linkWiki(_ text: String, wiki: (String) -> String?) -> String {
        guard text.contains("[[") else { return text }
        var out: [String] = []
        var fence: String?
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                let f = String(t.prefix(3))
                if fence == nil { fence = f } else if fence == f { fence = nil }
                out.append(line); continue
            }
            if fence != nil || !line.contains("[[") { out.append(line); continue }
            // leave `code spans` alone: only the pieces between backticks are changed
            let pieces = line.components(separatedBy: "`")
            out.append(pieces.enumerated().map { i, p in i % 2 == 0 ? replace(p, wiki: wiki) : p }.joined(separator: "`"))
        }
        return out.joined(separator: "\n")
    }

    private static func replace(_ s: String, wiki: (String) -> String?) -> String {
        var result = s
        for (range, link) in WikiLink.parse(s).reversed() {
            let shown = link.alias ?? link.note
            if let path = wiki(link.note) {
                let enc = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
                let label = shown.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                result.replaceSubrange(range, with: "[\(label)](\(wikiScheme)\(enc))")
            } else {
                result.replaceSubrange(range, with: shown)
            }
        }
        return result
    }

    // MARK: base folder

    private struct Rebase: MarkupRewriter {
        let base: String?

        func target(_ d: String?) -> String? {
            guard let d, !d.isEmpty else { return d }
            if d.hasPrefix(wikiScheme) { return String(d.dropFirst(wikiScheme.count)) }
            guard let base, !base.isEmpty, LinkPolicy.scheme(of: d) == nil, !d.hasPrefix("/"), !d.hasPrefix("#"), !d.hasPrefix("?"), !d.hasPrefix("\\") else { return d }
            // join, resolving `..` so the result stays below the opened folder; a link that would leave it loses its target
            var parts = base.split(separator: "/").map(String.init)
            let (path, suffix) = split(d)
            for raw in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
                let p = raw.removingPercentEncoding ?? raw
                if p == ".." { if parts.isEmpty { return nil }; parts.removeLast() }
                else if p != "." { parts.append(p) }
            }
            return parts.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }.joined(separator: "/") + suffix
        }

        /// The path part and the `?query` or `#fragment` that follows it.
        private func split(_ d: String) -> (String, String) {
            guard let i = d.firstIndex(where: { $0 == "?" || $0 == "#" }) else { return (d, "") }
            return (String(d[..<i]), String(d[i...]))
        }

        mutating func visitLink(_ link: Markdown.Link) -> Markup? {
            var l = link
            l.destination = target(link.destination)
            return defaultVisit(l)
        }

        mutating func visitImage(_ image: Markdown.Image) -> Markup? {
            var i = image
            i.source = target(image.source)
            return defaultVisit(i)
        }
    }
}
