import AppKit
import WebKit
import Markdown

/// HTML export, printing (which also saves PDF) and copying the Markdown.
@MainActor
final class Exporter: NSObject, WKNavigationDelegate {
    static let shared = Exporter()
    private var web: WKWebView?
    private var printWindow: NSWindow?

    /// A full HTML page for the note, set the way the viewer sets it. [[Wiki links]] become their plain text.
    nonisolated static func html(markdown: String, title: String, viewerFont: String = "Source Serif 4", size: Double = 18) -> String {
        let body = HTMLFormatter.format(Document(parsing: plainWikiLinks(markdown)))
        let esc = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(esc)</title>
        <style>
        body { font: \(Int(size))px/1.65 "\(viewerFont)", "New York", Georgia, serif; color: #24272B; max-width: 640px; margin: 48px auto; padding: 0 24px; }
        h1 { font-size: 2em; line-height: 1.2; } h2 { font-size: 1.33em; margin-top: 1.6em; } h3 { font-size: 1.11em; }
        blockquote { margin: 0; padding: 2px 0 2px 20px; border-left: 3px solid #D7DCE2; color: #4A4F56; font-style: italic; }
        code { font: 0.85em "IBM Plex Mono", ui-monospace, Menlo, monospace; background: #F2F4F7; border-radius: 4px; padding: 1px 5px; }
        pre { background: #F2F4F7; border-radius: 8px; padding: 12px; overflow-x: auto; } pre code { background: none; padding: 0; }
        table { border-collapse: collapse; } th, td { border: 1px solid #D7DCE2; padding: 6px 12px; } th { background: #F2F4F7; }
        a { color: #2F6FDB; } img { max-width: 100%; } hr { border: 0; border-top: 1px solid #D7DCE2; }
        </style></head><body>
        \(body)
        </body></html>
        """
    }

    nonisolated static func plainWikiLinks(_ s: String) -> String {
        var fenced = false
        return s.components(separatedBy: "\n").map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { fenced.toggle(); return line }
            if fenced { return line }
            var out = line
            for (r, w) in WikiLink.parse(line).reversed() { out.replaceSubrange(r, with: w.shown) }
            return out
        }.joined(separator: "\n")
    }

    func saveHTML(markdown: String, name: String, prefs: Preferences) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name + ".html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = Self.html(markdown: markdown, title: name, viewerFont: prefs.viewerFont, size: prefs.viewerSize)
        try? html.write(to: url, atomically: true, encoding: .utf8)
    }

    func copyMarkdown(_ markdown: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    /// The print panel; its PDF menu saves a PDF.
    func print(markdown: String, name: String, prefs: Preferences) {
        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        w.navigationDelegate = self
        web = w
        w.loadHTMLString(Self.html(markdown: markdown, title: name, viewerFont: prefs.viewerFont, size: prefs.viewerSize), baseURL: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            let info = NSPrintInfo.shared.copy() as! NSPrintInfo
            info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 54; info.rightMargin = 54
            let op = webView.printOperation(with: info)
            op.view?.frame = NSRect(x: 0, y: 0, width: 612, height: 792)
            op.showsPrintPanel = true
            if let win = NSApp.keyWindow { op.runModal(for: win, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
            self.web = nil
        }
    }
}
