import Foundation

struct OutlineHeading: Identifiable, Equatable {
    var level: Int
    var title: String
    var location: Int       // UTF-16 offset of the line, for jumping
    var id: Int { location }
}

enum Outline {
    /// The headings of a note, skipping anything inside a code fence.
    static func headings(in text: String) -> [OutlineHeading] {
        var out: [OutlineHeading] = []
        var fenced = false
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            let s = ns.substring(with: line)
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { fenced.toggle(); return }
            guard !fenced, s.hasPrefix("#") else { return }
            let level = s.prefix { $0 == "#" }.count
            guard level <= 6, s.dropFirst(level).first == " " else { return }
            let title = s.dropFirst(level).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { out.append(OutlineHeading(level: level, title: title, location: line.location)) }
        }
        return out
    }
}
