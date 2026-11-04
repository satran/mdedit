import SwiftUI

struct DetailView: View {
    @EnvironmentObject var ws: Workspace
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var document: DocumentStore
    /// `.mdedit/preview.css` of the opened folder, read again when the folder changes.
    @State private var customCSS: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                banner
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                if prefs.showStatusBar { footer }
            }
            .frame(width: ws.pinnedMainWidth)
            if ws.panelOnScreen != nil { RightPanelView(document: document) }
        }
        .background(Color(Palette.paneBg))
        .onAppear { customCSS = CustomCSS.load(ws.rootURL) }
        .onChange(of: ws.treeVersion) { _, _ in
            let c = CustomCSS.load(ws.rootURL)
            if c != customCSS { customCSS = c }
        }
    }

    // MARK: header

    private var headerDivider: some View { Rectangle().fill(Color(Palette.binderBorder)).frame(width: 1, height: 18) }

    private var header: some View {
        let name = document.url?.deletingPathExtension().lastPathComponent ?? ""
        // a web page is only shown: nothing here works on Markdown, so the buttons stay, dimmed
        let canExport = document.url != nil && !ws.showingHTML
        return HStack(spacing: 12) {
            IconButton(symbol: "sidebar.left", label: ws.binderVisible ? "Hide binder" : "Show binder") { ws.toggleBinder() }
                .foregroundStyle(Color(ws.binderVisible ? Palette.link : Palette.muted))
            headerDivider
            IconButton(symbol: "chevron.left", label: "Back to previous note") { ws.goBack() }
                .foregroundStyle(Color(Palette.muted)).opacity(ws.visited.isEmpty ? 0.35 : 1).disabled(ws.visited.isEmpty)
            breadcrumb.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                IconButton(symbol: "eye", label: ws.mode == .view ? "Back to writing" : "Preview") { ws.mode = ws.mode == .view ? .write : .view }
                    .foregroundStyle(Color(ws.mode == .view ? Palette.link : Palette.muted))
                    .opacity(ws.showingHTML ? 0.35 : 1).disabled(ws.showingHTML)
                    .accessibilityAddTraits(ws.mode == .view ? .isSelected : [])
                shareMenu(name: name).opacity(canExport ? 1 : 0.35).disabled(!canExport)
                IconButton(symbol: "square.on.square", label: "New window with this folder") { ws.openInNewWindow() }
                    .foregroundStyle(Color(Palette.muted)).disabled(ws.root == nil)
            }
            headerDivider
            IconButton(symbol: "sidebar.right", label: ws.panel == nil ? "Show side panel" : "Hide side panel") { ws.togglePanel() }
                .foregroundStyle(Color(ws.panel != nil ? Palette.link : Palette.muted))
                .accessibilityAddTraits(ws.panel != nil ? .isSelected : [])
        }
        .padding(.leading, ws.binderVisible ? 16 : 100).padding(.trailing, 16)
        .animation(.easeInOut(duration: 0.25), value: ws.binderVisible)
        .frame(height: Metrics.headerHeight)
        .background(WindowDragArea())
    }

    private func shareMenu(name: String) -> some View {
        Menu {
            Button("Export as HTML…") { Exporter.shared.saveHTML(markdown: document.text, name: name, prefs: prefs) }
            Button("Copy as Markdown") { Exporter.shared.copyMarkdown(document.text) }
            Divider()
            Button("Print… (PDF in the print panel)") { Exporter.shared.print(markdown: document.text, name: name, prefs: prefs) }
        } label: {
            Image(systemName: "square.and.arrow.up").font(.system(size: 13)).frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30)
        .foregroundStyle(Color(Palette.muted))
        .accessibilityLabel("Share").help("Share")
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
            PreviewWebView(request: previewRequest, open: openLink)
        }
    }

    private var previewRequest: PreviewRequest {
        let url = document.url
        let source: PreviewRequest.Source = ws.showingHTML && url != nil ? .html(url!, text: document.text) : .markdown(document.text)
        return PreviewRequest(source: source, title: url?.deletingPathExtension().lastPathComponent ?? "", noteFolder: url?.deletingLastPathComponent(),
                              root: ws.rootURL, options: .init(style: prefs.viewerStyle, loadRemote: prefs.loadRemoteImages, customCSS: ws.showingHTML ? nil : customCSS))
    }

    /// A click in the preview: the same rules for notes and pages.
    private func openLink(_ url: URL) {
        switch LinkPolicy.decide(url, noteFolder: document.url?.deletingLastPathComponent(), root: ws.rootURL) {
        case .wiki(let t): ws.openWiki(t)
        case .openWeb(let u): NSWorkspace.shared.open(u)
        case .selectNote(let u): ws.select(u)
        case .openFile(let u): NSWorkspace.shared.open(u)
        case .reveal(let u): NSWorkspace.shared.activateFileViewerSelecting([u])
        case .ignore: break
        }
    }

    // MARK: footer

    private var footer: some View {
        let page = ws.showingHTML
        let words = DocumentStore.wordCount(page ? HTMLText.visible(document.text) : document.text)
        return HStack(spacing: 2) {
            if document.url != nil {
                Text("\(words) \(words == 1 ? "word" : "words") · \(DocumentStore.readMinutes(words: words)) min read")
            }
            Spacer()
            if document.url != nil, !page, ws.mode == .write {
                IconButton(symbol: "circle.circle", label: "Distraction free") { ws.toggleFocus() }
                IconButton(symbol: "text.alignleft", label: ws.typewriter ? "Turn off typewriter mode" : "Typewriter mode") { ws.typewriter.toggle(); DispatchQueue.main.async { ws.focusEditor() } }
                    .foregroundStyle(Color(ws.typewriter ? Palette.link : Palette.muted))
            }
        }
        .font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
        .padding(.leading, 28).padding(.trailing, 12)
        .frame(height: Metrics.footerHeight)
        .overlay(alignment: .top) { Rectangle().fill(Color(Palette.paneBorder)).frame(height: 1) }
    }
}
