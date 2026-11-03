import SwiftUI

/// The manual (`Resources/Manual.md`) cut into pages at its `##` headings, plus a shortcuts page made from the live
/// command list, so the keys shown can never differ from the keys in the menus.
enum HelpManual {
    struct Page: Identifiable, Hashable {
        let title: String
        let markdown: String
        var id: String { title }
    }

    private final class Token {}

    static var source: String {
        guard let url = Bundle(for: Token.self).url(forResource: "Manual", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "# MDEdit Manual\n\nThe manual could not be found." }
        return text
    }

    static func pages(source: String = source, commands: [Cmd]) -> [Page] {
        var pages: [Page] = []
        var title: String?
        var body: [String] = []
        func flush() { if let t = title { pages.append(Page(title: t, markdown: "# " + t + "\n\n" + body.joined(separator: "\n"))) } }
        for line in source.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { flush(); title = String(line.dropFirst(3)); body = [] }
            else if title != nil { body.append(line) }
        }
        flush()
        let keyed = commands.filter { $0.key != nil }
        if !keyed.isEmpty {
            let rows = keyed.map { "| \($0.title) | \($0.shortcut) |" }.joined(separator: "\n")
            pages.append(Page(title: "Keyboard shortcuts", markdown: "# Keyboard shortcuts\n\nEvery command is also in the menus and in the command palette (⇧⌘P).\n\n| Command | Shortcut |\n| --- | --- |\n" + rows))
        }
        return pages
    }
}

/// Help ▸ MDEdit Help: pages on the left, the chosen page set in the viewer's reading template on the right.
struct HelpView: View {
    @EnvironmentObject var prefs: Preferences
    @State private var pages: [HelpManual.Page] = []
    @State private var selected: String?
    @State private var query = ""

    private var shown: [HelpManual.Page] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? pages : pages.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.markdown.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(shown, selection: $selected) { Text($0.title).tag($0.id) }
                .safeAreaInset(edge: .top) {
                    TextField("Search the manual", text: $query).textFieldStyle(.roundedBorder).padding(8)
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            if let page = shown.first(where: { $0.id == selected }) ?? shown.first {
                HelpPage(markdown: page.markdown, prefs: prefs).id(page.id)
            } else {
                Text("Nothing in the manual matches “\(query)”.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            guard pages.isEmpty else { return }
            pages = HelpManual.pages(commands: makeCommands(ws: nil, prefs: prefs, recents: RecentFolders.shared, newWindow: { _ in }))
            selected = pages.first?.id
        }
    }
}

private struct HelpPage: View {
    let markdown: String
    @ObservedObject var prefs: Preferences
    var body: some View {
        PreviewWebView(request: PreviewRequest(source: .markdown(markdown), title: "MDEdit Help", noteFolder: nil, root: nil,
                                               options: .init(style: prefs.viewerStyle, loadRemote: false, customCSS: nil)),
                       open: { url in if ["http", "https"].contains(url.scheme) { NSWorkspace.shared.open(url) } })
    }
}
