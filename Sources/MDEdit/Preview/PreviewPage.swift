import AppKit
import Foundation
import Markdown

/// The page the preview shows for a note: the note as safe HTML, set with the type specs of `ViewerStyle` as CSS.
/// Everything here is pure text in, text out, so it is tested without a window.
enum PreviewPage {
    struct Options {
        var style: ViewerStyle
        var loadRemote = false
        var customCSS: String?
    }

    /// Pages, pictures, fonts and HTML files all load through this scheme (see `PreviewFiles`), so the app decides what may be read.
    static let scheme = "mdedit-file"

    /// `mdedit-file://local/Users/me/notes/pic.png` for a file; `mdedit-file://bundle/Literata.ttf` for a font in the app.
    static func url(forFile file: URL, directory: Bool = false) -> URL {
        let path = file.standardizedFileURL.path
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(scheme)://local\(encoded)\(directory && !encoded.hasSuffix("/") ? "/" : "")")!
    }

    /// The file a page address stands for, or nil for any other address.
    static func file(from url: URL) -> URL? {
        guard url.scheme == scheme, url.host == "local" else { return nil }
        let path = url.path(percentEncoded: false)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    // MARK: page

    static func html(markdown: String, title: String, options: Options) -> String {
        let esc = SafeHTML.escape(title)
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp(loadRemote: options.loadRemote))">
        <meta name="referrer" content="no-referrer"><title>\(esc)</title>
        <style>
        \(css(options.style))
        </style>
        \(custom(options.customCSS))</head><body><main>
        \(body(markdown: markdown))</main></body></html>
        """
    }

    /// What a page may load. Scripts never; pictures, styles and fonts from the folder, and from the web only when asked.
    static func csp(loadRemote: Bool) -> String {
        let web = loadRemote ? " https: http:" : ""
        return "default-src 'none'; script-src 'none'; img-src \(scheme): data:\(web); style-src 'unsafe-inline' \(scheme):\(web); "
            + "font-src \(scheme): data:\(web); media-src \(scheme):\(web); form-action 'none'; base-uri 'none'"
    }

    /// The same list as a header, for HTML files, which are served as they are and cannot carry a tag of ours.
    static func headerCSP(loadRemote: Bool) -> String {
        let web = loadRemote ? " https: http:" : ""
        return "script-src 'none'; object-src 'none'; form-action 'none'; connect-src 'none'; "
            + "img-src \(scheme): data: blob:\(web); style-src 'unsafe-inline' \(scheme):\(web); font-src \(scheme): data:\(web); media-src \(scheme): blob:\(web)"
    }

    static let maxCustomCSS = 256 * 1024

    private static func custom(_ css: String?) -> String {
        guard var c = css, !c.isEmpty else { return "" }
        if c.utf8.count > maxCustomCSS { c = String(decoding: Array(c.utf8.prefix(maxCustomCSS)), as: UTF8.self) }
        // the sheet is the reader's own, but it must not be able to close its element and add markup
        c = c.replacingOccurrences(of: "</style", with: "<\\/style", options: .caseInsensitive)
        return "<style id=\"custom\">\n\(c)\n</style>\n"
    }

    /// The note's front matter as a properties card, then the Markdown as HTML.
    static func body(markdown: String) -> String {
        var text = markdown
        var out = ""
        if let fm = FrontMatter.parse(markdown) {
            out += properties(fm)
            text = (markdown as NSString).substring(from: fm.end)
        }
        return out + SafeHTML.render(Document(parsing: MarkdownLimits.clamp(text), options: [.disableSmartOpts]), preview: true)
    }

    private static func properties(_ fm: FrontMatter) -> String {
        let rows = fm.properties.map { p -> String in
            let v: String
            switch p.value {
            case .text(let t): v = PreviewText.linkified(t, smart: false)
            case .bool(let b): v = b ? "<span class=\"yes\">&#9745;</span>" : "<span class=\"no\">&#9744;</span>"
            case .list(let l): v = l.map { "<span class=\"chip\">\(PreviewText.linkified($0, smart: false))</span>" }.joined(separator: " ")
            }
            return "<tr><th>\(SafeHTML.escape(p.key))</th><td>\(v)</td></tr>"
        }
        return "<div class=\"props\"><table>\(rows.joined())</table></div>\n"
    }

    // MARK: style

    private static func hex(_ c: NSColor, dark: Bool, alpha: Bool = false) -> String {
        var out = "#000000"
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let s = c.usingColorSpace(.sRGB) else { return }
            func b(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
            out = String(format: "#%02X%02X%02X", b(s.redComponent), b(s.greenComponent), b(s.blueComponent))
            if alpha { out += "59" }
        }
        return out
    }

    private static func num(_ v: CGFloat) -> String {
        let r = (Double(v) * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    private static func colors(_ s: ViewerStyle, dark: Bool) -> String {
        let table: [(String, NSColor)] = [
            ("pane", Palette.paneBg), ("ink", s.ink), ("head", s.headingInk), ("secondary", s.secondaryInk), ("quote", s.quoteInk),
            ("bar", Palette.vQuoteBar), ("bullet", s.bulletInk), ("rule", Palette.vRule), ("rowline", Palette.vRowLine),
            ("label", Palette.vLabel), ("chip", Palette.vChip), ("card", Palette.vCard), ("band", Palette.codeBand),
            ("code", Palette.codeInk), ("link", Palette.linkText), ("green", Palette.green), ("muted", Palette.muted), ("done", Palette.done),
        ]
        return table.map { "--\($0.0): \(hex($0.1, dark: dark));" }.joined(separator: " ")
            + " --link-line: \(hex(Palette.linkText, dark: dark, alpha: true));"
    }

    /// Fonts that ship in the app, served by `PreviewFiles` from the bundle.
    static let fontFaces: [(family: String, file: String, style: String, weight: String)] = [
        ("Literata", "Literata.ttf", "normal", "200 900"), ("Literata", "Literata-Italic.ttf", "italic", "200 900"),
        ("Inter", "Inter.ttf", "normal", "100 900"), ("Inter", "Inter-Italic.ttf", "italic", "100 900"),
        ("IBM Plex Mono", "IBMPlexMono-Regular.ttf", "normal", "400"), ("IBM Plex Mono", "IBMPlexMono-Italic.ttf", "italic", "400"),
        ("IBM Plex Mono", "IBMPlexMono-SemiBold.ttf", "normal", "600"), ("IBM Plex Mono", "IBMPlexMono-Bold.ttf", "normal", "700"),
    ]

    static func css(_ s: ViewerStyle) -> String {
        let faces = fontFaces.map {
            "@font-face { font-family: \"\($0.family)\"; src: url(\(scheme)://bundle/\($0.file)); font-style: \($0.style); font-weight: \($0.weight); }"
        }.joined(separator: "\n")
        let serif = s.isSerif
        let h1 = s.heading(1), h2 = s.heading(2), h3 = s.heading(3), h4 = s.heading(4)
        func head(_ sel: String, _ h: ViewerStyle.Heading) -> String {
            let w = h.weight == .bold ? 700 : 600
            return "\(sel) { font-size: \(num(h.size))px; line-height: \(num(h.leading)); font-weight: \(w); letter-spacing: \(num(h.tracking))em; margin: \(num(h.top))px 0 \(num(h.bottom))px; color: var(--head); }"
        }
        let family = serif ? "\"Literata\", \"New York\", ui-serif, Georgia, serif" : "\"Inter\", system-ui, -apple-system, sans-serif"
        let mono = "\"IBM Plex Mono\", ui-monospace, Menlo, monospace"
        let bullet = serif
            ? "ul > li::before { content: \"\\2022\"; position: absolute; left: \(num(s.body * 0.2))px; color: var(--bullet); }"
            : "ul > li::before { content: \"\"; position: absolute; left: \(num(s.body * 0.25))px; top: 0.62em; width: 5px; height: 5px; border-radius: 50%; background: var(--bullet); }"
        let quote = serif
            ? "blockquote { margin: 0 0 \(num(s.quoteGap))px; padding: 0 \(num(s.quoteIndent))px; font-size: \(num(s.quoteSize))px; line-height: \(num(s.quoteLeading)); color: var(--quote); }"
            : "blockquote { margin: 0 0 \(num(s.quoteGap))px; padding: 2px 0 2px \(num(s.quotePadding))px; border-left: \(num(s.quoteBar))px solid var(--bar); font-size: \(num(s.quoteSize))px; line-height: \(num(s.quoteLeading)); color: var(--quote); }"
        let colWeight = serif ? "" : "td:first-child { font-weight: 500; }"
        return """
        \(faces)
        :root { color-scheme: light dark; \(colors(s, dark: false)) }
        @media (prefers-color-scheme: dark) { :root { \(colors(s, dark: true)) } }
        * { box-sizing: border-box; }
        html { background: var(--pane); -webkit-text-size-adjust: none; }
        body { margin: 0; padding: \(num(s.pageTop))px 24px \(num(s.pageBottom + 24))px; background: var(--pane); color: var(--ink);
               font: \(num(s.body))px/\(num(s.bodyLeading)) \(family); font-variant-numeric: \(serif ? "oldstyle-nums" : "normal");
               -webkit-font-smoothing: antialiased; overflow-wrap: break-word; }
        main { max-width: \(num(s.measure))px; margin: 0 auto; }
        main > :first-child { margin-top: 0; }
        p { margin: 0 0 \(num(s.paragraphGap))px; }
        \(head("h1", h1))
        \(head("h2", h2))
        \(head("h3", h3))
        \(head("h4, h5, h6", h4))
        \(quote)
        blockquote > :last-child { margin-bottom: 0; }
        ul, ol { margin: 0 0 \(num(s.paragraphGap))px; padding: 0; }
        ul { list-style: none; }
        ol { padding-left: \(num(s.body * 1.7))px; }
        ol > li::marker { color: var(--bullet); font-variant-numeric: lining-nums tabular-nums; }
        li { position: relative; margin: 0 0 \(num(s.itemGap))px; }
        ul > li { padding-left: \(num(s.itemIndent))px; }
        li > p { margin: 0; }
        li > p + p { margin-top: \(num(s.paragraphGap))px; }
        li > ul, li > ol { margin: \(num(s.itemGap))px 0 0; }
        \(bullet)
        li:has(> input[type=checkbox])::before { content: none; }
        li > input[type=checkbox] { position: absolute; left: 0; top: 0.42em; margin: 0; width: 0.85em; height: 0.85em; accent-color: var(--green); }
        li:has(> input[type=checkbox]:checked) { color: var(--done); text-decoration: line-through; }
        pre { margin: \(num(s.codeTop))px 0 \(num(s.codeBottom))px; padding: 16px 20px; background: var(--band); border-radius: 8px; overflow-x: auto;
              font: \(num(s.codeSize))px/\(num(s.codeLeading)) \(mono); color: var(--code); font-variant-numeric: normal; }
        code { font-family: \(mono); font-size: \(num(s.inlineCodeScale))em; background: var(--chip); color: var(--code); border-radius: 4px; padding: 1px 5px; font-variant-numeric: normal; }
        pre code { font-size: inherit; background: none; padding: 0; border-radius: 0; }
        a { color: var(--link); text-decoration: underline; text-decoration-color: var(--link-line); text-underline-offset: 2px; }
        hr { width: 96px; height: 1px; border: 0; background: var(--rule); margin: \(num(s.ruleGap))px auto; }
        img { display: block; max-width: 100%; height: auto; margin: \(num(s.body * 0.25))px auto \(num(s.body * 0.75))px; }
        table { width: 100%; border-collapse: collapse; margin: \(num(s.tableTop))px 0 \(num(s.tableBottom))px;
                font-size: \(num(s.tableSize))px; line-height: \(num(s.tableLeading)); font-variant-numeric: lining-nums tabular-nums; }
        th { font: 600 \(num(s.tableLabelSize))px/1.3 system-ui, -apple-system, sans-serif; text-transform: uppercase; letter-spacing: \(num(s.tableLabelSize * s.tableLabelTracking))px;
             color: var(--label); text-align: left; padding: 0 16px 9px 0; border-bottom: 1px solid var(--rule); }
        td { padding: 10px 16px 10px 0; vertical-align: top; border-bottom: 1px solid var(--rowline); }
        th:last-child, td:last-child { padding-right: 0; }
        tbody tr:last-child td { border-bottom: 0; }
        td:nth-child(2) { color: var(--secondary); }
        \(colWeight)
        [align=center] { text-align: center; } [align=right] { text-align: right; }
        .props { margin: 0 0 \(num(s.propertiesBottom))px; border: 1px solid var(--card); border-radius: 10px; overflow: hidden;
                 font: \(num(14 * s.scale))px/1.4 system-ui, -apple-system, sans-serif; font-variant-numeric: normal; }
        .props table { margin: 0; font: inherit; }
        .props th { width: 150px; padding: 10px 16px; font: inherit; text-transform: none; letter-spacing: 0; color: var(--label); border: 0; vertical-align: middle; }
        .props td { padding: 10px 16px 10px 0; color: var(--ink); border: 0; vertical-align: middle; }
        .props tr + tr th, .props tr + tr td { border-top: 1px solid var(--rowline); }
        .props .chip { display: inline-block; padding: 2px 10px; margin: 1px 4px 1px 0; border-radius: 999px; background: var(--chip); font-size: 0.93em; }
        .props .yes { color: var(--green); } .props .no { color: var(--muted); }
        """
    }
}

/// Plain text in a note, as the preview sets it: real punctuation, `[[wiki links]]` and bare web addresses as links.
enum PreviewText {
    private static let bareURL = try! NSRegularExpression(pattern: "https?://[^\\s<>\\]]+")

    /// The HTML for a run of text, and the character it ends with (for the quote that follows).
    static func html(_ text: String, previous: Character?, inLink: Bool) -> (String, Character?) {
        if inLink { return (insideLink(text, previous: previous), SmartPunctuation.apply(text, previous: previous).last) }
        var last: Character?
        let h = linkified(text, previous: previous, last: &last)
        return (h, last)
    }

    /// The words of a link are prose; a web address shown as the link is not.
    private static func insideLink(_ s: String, previous: Character?) -> String {
        let isAddress = s.contains("://") || s.lowercased().hasPrefix("www.") || s.hasPrefix("mailto:")
        return SafeHTML.escape(isAddress ? s : SmartPunctuation.apply(s, previous: previous))
    }

    private static func anchor(_ href: String?, _ text: String) -> String {
        guard let href, let target = SafeHTML.safeTarget(href) else { return SafeHTML.escape(text) }
        return "<a href=\"\(target)\">\(SafeHTML.escape(text))</a>"
    }

    /// Wiki links keep the app's own address form, so a click is told from a web link.
    static func linkified(_ s: String, smart: Bool = true) -> String {
        var last: Character?
        return linkified(s, previous: nil, smart: smart, last: &last)
    }

    static func linkified(_ s: String, previous: Character?, smart: Bool = true, last end: inout Character?) -> String {
        func punct(_ t: String, _ before: Character?) -> String { smart ? SmartPunctuation.apply(t, previous: before) : t }
        var pieces: [(Range<String.Index>, String, String?, Bool)] = []
        let wikis = WikiLink.parse(s)
        for (r, w) in wikis { pieces.append((r, w.shown, w.url?.absoluteString, true)) }
        let ns = s as NSString
        // wiki links come in order, so overlap is found by walking both lists once (a note with thousands of addresses was quadratic)
        var w = 0
        for m in bareURL.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard var r = Range(m.range, in: s) else { continue }
            // trailing punctuation belongs to the sentence, not the address; a quote only when it has no partner inside the address
            while s[r].count > 1, let last = s[r].last, ".,;:!?)'\"".contains(last),
                  last != "'" && last != "\"" || s[r].filter({ $0 == last }).count % 2 == 1 {
                r = r.lowerBound..<s.index(before: r.upperBound)
            }
            while w < wikis.count, wikis[w].range.upperBound <= r.lowerBound { w += 1 }
            if w < wikis.count, wikis[w].range.overlaps(r) { continue }
            pieces.append((r, String(s[r]), String(s[r]), false))
        }
        guard !pieces.isEmpty else { let t = punct(s, previous); end = t.last; return SafeHTML.escape(t) }
        pieces.sort { $0.0.lowerBound < $1.0.lowerBound }
        var out = "", at = s.startIndex, last = previous
        func plain(_ t: String) { let p = punct(t, last); out += SafeHTML.escape(p); last = p.last ?? last }
        for (r, text, href, isWiki) in pieces {
            if at < r.lowerBound { plain(String(s[at..<r.lowerBound])) }
            if isWiki, let href { out += "<a href=\"\(SafeHTML.escape(href))\">\(SafeHTML.escape(text))</a>" } else { out += anchor(href, text) }
            last = text.last
            at = r.upperBound
        }
        if at < s.endIndex { plain(String(s[at...])) }
        end = last
        return out
    }
}

/// The reader's own stylesheet for the preview: `.mdedit/preview.css` in the opened folder.
enum CustomCSS {
    static func file(_ root: URL) -> URL { root.appendingPathComponent(".mdedit/preview.css") }

    private static func isLink(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false }

    /// The sheet's text; nil when there is none, it is a link, or it is too big or not text.
    static func load(_ root: URL?) -> String? {
        guard let root, !isLink(root.appendingPathComponent(".mdedit")), !isLink(file(root)),
              let h = try? FileHandle(forReadingFrom: file(root)) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: PreviewPage.maxCustomCSS + 1), data.count <= PreviewPage.maxCustomCSS, !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static let starter = """
    /* MDEdit preview stylesheet. It is added after the built-in one, so anything here wins.
       The preview of Markdown notes uses it; HTML files are shown as they are written. */

    /* Colours are variables, for light and dark mode:
       --pane --ink --head --secondary --quote --bar --bullet --rule --rowline --label --chip --card --band --code --link --green */

    /* main { max-width: 760px; } */
    /* h1, h2, h3 { font-family: "Inter", sans-serif; } */
    /* a { text-decoration: none; } */

    """

    /// Creates the starter sheet if there is none and returns the file. Nil when the folder does not allow it.
    @discardableResult static func createStarter(_ root: URL) -> URL? {
        let dir = root.appendingPathComponent(".mdedit", isDirectory: true), f = file(root)
        guard !isLink(dir), !isLink(f) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: f.path) {
            guard (try? Data(starter.utf8).write(to: f, options: .atomic)) != nil else { return nil }
        }
        return f
    }
}

/// The words of an HTML page, for the word count in the footer: tags, scripts and styles are left out.
enum HTMLText {
    private static let blocks = try! NSRegularExpression(pattern: "<(script|style)\\b[^>]*>.*?</\\1\\s*>|<!--.*?-->", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let tags = try! NSRegularExpression(pattern: "<[^>]*>")

    static func visible(_ html: String) -> String {
        var s = html.utf8.count > 4_000_000 ? String(decoding: Array(html.utf8.prefix(4_000_000)), as: UTF8.self) : html
        for r in [blocks, tags] { s = r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ") }
        return s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
    }
}
