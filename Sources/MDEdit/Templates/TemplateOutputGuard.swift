import Foundation

/// Layer 3 of the containment (plan 006): after a render, the output is read as tags and refused when it holds a tag that could open a
/// connection on its own. `dns-prefetch` and `preconnect` are not resource loads, so the header and the rule list are not known to stop
/// them, and a host name built from note text would leak it. This is a deny-list over tag names, a second line of defence and not a proof.
///
/// Refused: `<object>`, `<embed>`, `<iframe>`, `<frame>`, `<frameset>`, `<applet>`, `<base>`; `ping` on `<a>` and `<area>`; any `formaction`;
/// `<meta http-equiv>`; and every `<link>` except one whose `rel` is exactly `stylesheet` and whose `href` is relative.
enum TemplateOutputGuard {
    private static let refusedTags: Set<String> = ["object", "embed", "iframe", "frame", "frameset", "applet", "base"]
    private static let rawText: Set<String> = ["script", "style", "textarea", "title"]

    /// nil when the output may be shown; otherwise `.unsafe` naming the tag, with the line in the rendered output.
    static func check(_ html: String) -> TemplateError? {
        let c = Array(html.unicodeScalars)
        var i = 0, line = 1
        func isSpace(_ s: Unicode.Scalar) -> Bool { s == " " || s == "\t" || s == "\n" || s == "\r" || s == "\u{0C}" }
        func lower(_ s: Unicode.Scalar) -> Unicode.Scalar { ("A"..."Z").contains(s) ? Unicode.Scalar(s.value + 32)! : s }
        func has(_ text: String, at k: Int) -> Bool {
            let t = Array(text.unicodeScalars)
            guard k + t.count <= c.count else { return false }
            for j in 0..<t.count where lower(c[k + j]) != t[j] { return false }
            return true
        }
        func skip(to marker: String, from k: Int) -> Int {
            var j = k
            while j < c.count { if has(marker, at: j) { return j + marker.unicodeScalars.count }; j += 1 }
            return c.count
        }
        func newlines(_ a: Int, _ b: Int) -> Int { c[a..<min(b, c.count)].filter { $0 == "\n" }.count }

        while i < c.count {
            if c[i] != "<" { if c[i] == "\n" { line += 1 }; i += 1; continue }
            if has("<!--", at: i) { let e = skip(to: "-->", from: i + 4); line += newlines(i, e); i = e; continue }
            guard i + 1 < c.count else { break }
            let n = c[i + 1]
            if n == "/" || n == "!" || n == "?" { let e = skip(to: ">", from: i + 2); line += newlines(i, e); i = e; continue }
            guard ("a"..."z").contains(lower(n)) else { i += 1; continue }

            // a tag: name, then attributes up to the closing `>`
            let startLine = line
            var j = i + 1
            var name = ""
            while j < c.count, !isSpace(c[j]), c[j] != "/", c[j] != ">" { name.unicodeScalars.append(lower(c[j])); j += 1 }
            var attrs: [(name: String, value: String)] = []
            var closed = false
            while j < c.count {
                while j < c.count, isSpace(c[j]) || c[j] == "/" { if c[j] == "\n" { line += 1 }; j += 1 }
                if j >= c.count { break }
                if c[j] == ">" { closed = true; j += 1; break }
                var an = ""
                while j < c.count, !isSpace(c[j]), c[j] != "=", c[j] != ">", c[j] != "/" { an.unicodeScalars.append(lower(c[j])); j += 1 }
                while j < c.count, isSpace(c[j]) { if c[j] == "\n" { line += 1 }; j += 1 }
                var value = ""
                if j < c.count, c[j] == "=" {
                    j += 1
                    while j < c.count, isSpace(c[j]) { if c[j] == "\n" { line += 1 }; j += 1 }
                    if j < c.count, c[j] == "\"" || c[j] == "'" {
                        let q = c[j]; j += 1
                        while j < c.count, c[j] != q { if c[j] == "\n" { line += 1 }; value.unicodeScalars.append(c[j]); j += 1 }
                        j += 1
                    } else {
                        while j < c.count, !isSpace(c[j]), c[j] != ">" { value.unicodeScalars.append(c[j]); j += 1 }
                    }
                }
                if an.isEmpty { j += 1; continue }
                attrs.append((an, value))
            }
            if let bad = verdict(name, attrs) { return .unsafe(tag: bad, line: startLine) }
            i = j
            if !closed { break }
            if rawText.contains(name) { let e = skip(to: "</" + name, from: i); line += newlines(i, e); i = e }
        }
        return nil
    }

    private static func verdict(_ name: String, _ attrs: [(name: String, value: String)]) -> String? {
        if refusedTags.contains(name) { return "<\(name)>" }
        if attrs.contains(where: { $0.name == "formaction" }) { return "formaction" }
        switch name {
        case "a", "area":
            if attrs.contains(where: { $0.name == "ping" }) { return "<\(name) ping>" }
        case "meta":
            if attrs.contains(where: { $0.name == "http-equiv" }) { return "<meta http-equiv>" }
        case "link":
            guard let rel = attrs.first(where: { $0.name == "rel" })?.value, let relDecoded = decode(rel),
                  relDecoded.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).map(String.init) == ["stylesheet"],
                  let href = attrs.first(where: { $0.name == "href" })?.value, let hrefDecoded = decode(href), isRelative(hrefDecoded)
            else { return "<link>" }
        default: break
        }
        return nil
    }

    /// The value with character references resolved, or nil when it holds one that is not understood (then the tag is refused).
    static func decode(_ s: String) -> String? {
        guard s.contains("&") else { return s }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "sol": "/", "bsol": "\\", "colon": ":", "Tab": "\t", "NewLine": "\n"]
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            guard let semi = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: semi) <= 10 else { return nil }
            let body = String(after[..<semi])
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let value: UInt32?
                if digits.hasPrefix("x") || digits.hasPrefix("X") { value = UInt32(digits.dropFirst(), radix: 16) } else { value = UInt32(digits, radix: 10) }
                guard let v = value, let u = Unicode.Scalar(v) else { return nil }
                out.unicodeScalars.append(u)
            } else if let r = named[body] { out += r } else { return nil }
            rest = after[after.index(after: semi)...]
        }
        return out + rest
    }

    /// No scheme and not starting with `/`, `\` or `//`, after removing whitespace and control characters (browsers ignore them).
    static func isRelative(_ href: String) -> Bool {
        let h = String(href.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) })
        if h.isEmpty || h.hasPrefix("/") || h.hasPrefix("\\") { return false }
        if let stop = h.firstIndex(where: { ":/?#".contains($0) }), h[stop] == ":" { return false }
        return true
    }
}
