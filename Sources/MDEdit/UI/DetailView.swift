import SwiftUI

struct DetailView: View {
    @EnvironmentObject var ws: Workspace
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var document: DocumentStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                banner
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                if prefs.showStatusBar { footer }
            }
            if ws.outlineVisible {
                Rectangle().fill(Color(Palette.binderBorder)).frame(width: 1)
                OutlineView(document: document).frame(width: 240)
            }
        }
        .background(Color(Palette.paneBg))
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            IconButton(symbol: "sidebar.left", label: ws.binderVisible ? "Hide binder" : "Show binder") { ws.toggleBinder() }
                .foregroundStyle(Color(ws.binderVisible ? Palette.link : Palette.muted))
            breadcrumb.frame(maxWidth: .infinity, alignment: .leading)
            IconButton(symbol: "eye", label: ws.mode == .view ? "Back to writing" : "Preview") { ws.mode = ws.mode == .view ? .write : .view }
                .foregroundStyle(Color(ws.mode == .view ? Palette.link : Palette.muted))
                .accessibilityAddTraits(ws.mode == .view ? .isSelected : [])
            IconButton(symbol: "square.on.square", label: "New window with this folder") { ws.openInNewWindow() }
                .foregroundStyle(Color(Palette.muted)).disabled(ws.root == nil)
            IconButton(symbol: "sidebar.right", label: ws.outlineVisible ? "Hide outline" : "Show outline") { ws.toggleOutline() }
                .foregroundStyle(Color(ws.outlineVisible ? Palette.link : Palette.muted))
        }
        .padding(.leading, ws.binderVisible ? 16 : 100).padding(.trailing, 16)
        .frame(height: Metrics.headerHeight)
        .background(WindowDragArea())
    }

    private var breadcrumb: some View {
        let parts = ws.breadcrumb
        return HStack(spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Color(Palette.marker)) }
                Text(p).fontWeight(i == parts.count - 1 ? .medium : .regular)
                    .foregroundStyle(Color(i == parts.count - 1 ? Palette.binderText : Palette.muted))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Location: " + parts.joined(separator: ", "))
    }

    // MARK: banners

    @ViewBuilder private var banner: some View {
        if document.changedOnDisk {
            bar("This note changed on disk.", actions: [("Keep mine", document.keepMine), ("Reload", document.reloadFromDisk)])
        } else if let e = document.error {
            bar(e, actions: [])
        }
    }

    private func bar(_ text: String, actions: [(String, () -> Void)]) -> some View {
        HStack(spacing: 12) {
            Text(text).font(.system(size: 12.5))
            Spacer()
            ForEach(Array(actions.enumerated()), id: \.offset) { _, a in Button(a.0, action: a.1).controlSize(.small) }
        }
        .padding(.horizontal, 28).frame(height: 34)
        .background(Color(Palette.chip))
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        if document.url == nil {
            Text(ws.root == nil ? "Open a folder to start" : "Select a note")
                .font(.system(size: 14)).foregroundStyle(Color(Palette.muted))
        } else if document.unreadable {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 24, weight: .light))
                Text(document.error ?? "This file cannot be opened.").font(.system(size: 13)).multilineTextAlignment(.center)
                Text("It has not been changed.").font(.system(size: 12))
            }
            .foregroundStyle(Color(Palette.muted)).padding(40)
        } else if ws.mode == .write {
            MarkdownTextEditor(text: $document.text, documentID: document.url,
                               style: EditorStyle(fontName: prefs.editorFont, size: CGFloat(prefs.editorSize), lineWidth: prefs.lineWidth, headingSizes: prefs.headingSizes),
                               onOpenWiki: { ws.openWiki($0) },
                               wikiResolves: { ws.wikiResolves($0) }, wikiNames: { ws.index.names },
                               linksVersion: ws.treeVersion, typewriter: ws.typewriter, bridge: ws.editor,
                               dropText: { ws.linkText(forDropped: $0) })
        } else {
            ViewerContainer(text: document.text, baseURL: document.url?.deletingLastPathComponent(), prefs: prefs)
                .environment(\.openURL, OpenURLAction { url in
                    switch LinkPolicy.decide(url, noteFolder: document.url?.deletingLastPathComponent(), root: ws.rootURL) {
                    case .wiki(let t): ws.openWiki(t)
                    case .openWeb(let u): NSWorkspace.shared.open(u)
                    case .selectNote(let u): ws.select(u)
                    case .openFile(let u): NSWorkspace.shared.open(u)
                    case .reveal(let u): NSWorkspace.shared.activateFileViewerSelecting([u])
                    case .ignore: break
                    }
                    return .handled
                })
        }
    }

    // MARK: footer

    private var footer: some View {
        let words = DocumentStore.wordCount(document.text)
        let name = document.url?.deletingPathExtension().lastPathComponent ?? ""
        return HStack(spacing: 2) {
            if document.url != nil {
                Text("\(words) \(words == 1 ? "word" : "words") · \(DocumentStore.readMinutes(words: words)) min read")
            }
            Spacer()
            if document.url != nil {
                if ws.mode == .write {
                    IconButton(symbol: "circle.circle", label: "Distraction free") { ws.toggleFocus() }
                    IconButton(symbol: "text.alignleft", label: ws.typewriter ? "Turn off typewriter mode" : "Typewriter mode") { ws.typewriter.toggle() }
                        .foregroundStyle(Color(ws.typewriter ? Palette.link : Palette.muted))
                } else {
                    IconButton(symbol: "printer", label: "Print") { Exporter.shared.print(markdown: document.text, name: name, prefs: prefs) }
                }
                Menu {
                    Button("Export as HTML…") { Exporter.shared.saveHTML(markdown: document.text, name: name, prefs: prefs) }
                    Button("Copy as Markdown") { Exporter.shared.copyMarkdown(document.text) }
                    Divider()
                    Button("Print… (PDF in the print panel)") { Exporter.shared.print(markdown: document.text, name: name, prefs: prefs) }
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 13)).frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30).accessibilityLabel("Export")
            }
        }
        .font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
        .padding(.leading, 28).padding(.trailing, 12)
        .frame(height: Metrics.footerHeight)
        .overlay(alignment: .top) { Rectangle().fill(Color(Palette.paneBorder)).frame(height: 1) }
    }
}

/// Parses once per change of text, not on every redraw.
struct ViewerContainer: View {
    let text: String
    let baseURL: URL?
    @ObservedObject var prefs: Preferences
    @State private var blocks: [VBlock] = []

    var body: some View {
        ViewerView(blocks: blocks, baseURL: baseURL, prefs: prefs)
            .onAppear { blocks = ViewerParser.parse(text) }
            .onChange(of: text) { _, new in blocks = ViewerParser.parse(new) }
    }
}
