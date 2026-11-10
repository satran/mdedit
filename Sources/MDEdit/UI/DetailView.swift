import SwiftUI

struct DetailView: View {
    @EnvironmentObject var ws: Workspace
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var document: DocumentStore
    @ObservedObject private var proposals = ProposalStore.shared
    /// `.mdedit/preview.css` of the opened folder, read again when the folder changes.
    @State private var customCSS: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                banner
                TemplateBanner(ws: ws)
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

    private var header: some View {
        // every icon button is the same distance from the next one: 4 pt between their 30 pt boxes, on both sides of the tabs
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                IconButton(symbol: "sidebar.left", label: ws.binderVisible ? "Hide binder" : "Show binder") { ws.toggleBinder() }
                    .foregroundStyle(Color(ws.binderVisible ? Palette.link : Palette.muted))
                IconButton(symbol: "chevron.left", label: "Back to previous note") { ws.goBack() }
                    .foregroundStyle(Color(Palette.muted)).opacity(ws.visited.isEmpty ? 0.35 : 1).disabled(ws.visited.isEmpty)
            }
            tabStrip
            HStack(spacing: 4) {
                IconButton(symbol: "plus", label: "New document") { ws.newDocument() }
                    .foregroundStyle(Color(Palette.muted)).opacity(ws.root == nil ? 0.35 : 1).disabled(ws.root == nil)
                IconButton(symbol: "eye", label: ws.mode == .view ? "Back to writing" : "Preview") { ws.mode = ws.mode == .view ? .write : .view }
                    .foregroundStyle(Color(ws.mode == .view ? Palette.link : Palette.muted))
                    .opacity(document.url == nil ? 0.35 : 1).disabled(document.url == nil)
                    .accessibilityAddTraits(ws.mode == .view ? .isSelected : [])
                IconButton(symbol: "sidebar.right", label: ws.panel == nil ? "Show side panel" : "Hide side panel") { ws.togglePanel() }
                    .foregroundStyle(Color(ws.panel != nil ? Palette.link : Palette.muted))
                    .accessibilityAddTraits(ws.panel != nil ? .isSelected : [])
            }
        }
        .padding(.leading, ws.binderVisible ? 16 : 100).padding(.trailing, 16)
        .animation(.easeInOut(duration: 0.25), value: ws.binderVisible)
        .frame(height: Metrics.headerHeight)
        .background(WindowDragArea())
    }

    /// The open notes as tabs filling the header; with one note or none, where it is.
    @ViewBuilder private var tabStrip: some View {
        if !ws.showsTabs {
            breadcrumb.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HeaderTabs(document: document)
        }
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
        InfoBar(text: text, actions: actions.map { InfoBar.Action(title: $0.0, run: $0.1) })
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
                               linksVersion: ws.treeVersion, typewriter: ws.typewriter && !ws.isCodeFile, code: ws.codeKind, bridge: ws.editor,
                               dropText: ws.isCodeFile ? nil : { ws.linkText(forDropped: $0) })
        } else {
            PreviewWebView(request: previewRequest, open: openLink)
        }
    }

    private var previewRequest: PreviewRequest {
        let url = document.url
        let title = url?.deletingPathExtension().lastPathComponent ?? ""
        let options = PreviewPage.Options(style: prefs.viewerStyle, loadRemote: prefs.loadRemoteImages, customCSS: nil)
        func shown(_ markdown: String) -> PreviewRequest {
            PreviewRequest(source: .markdown(markdown), title: title, noteFolder: ws.rootURL, root: ws.rootURL, options: .init(style: prefs.viewerStyle, loadRemote: false, customCSS: nil))
        }
        func template(_ html: String) -> PreviewRequest {
            PreviewRequest(source: .template(rendered: html), title: "", noteFolder: ws.rootURL, root: ws.rootURL, options: .init(style: prefs.viewerStyle, loadRemote: false, customCSS: nil))
        }
        switch ws.codeKind {
        case .json?: return shown(CodePreview.markdown(json: document.text))
        case .yaml?: return shown(CodePreview.markdown(yaml: document.text))
        case .html?:
            if ws.isTemplateCandidate {
                // a rendered template, or the page saying why there is none; while it renders the page is blank
                switch ws.templateState {
                case .rendered(let html): return template(html)
                case .failed(let e): return template(PreviewPage.errorPage(title: e.title, message: e.message, line: e.line))
                default: return shown("")
                }
            }
            return PreviewRequest(source: .html(url!, text: document.text), title: title, noteFolder: url?.deletingLastPathComponent(), root: ws.rootURL, options: options)
        case nil:
            return PreviewRequest(source: .markdown(document.text), title: title, noteFolder: url?.deletingLastPathComponent(), root: ws.rootURL,
                                  options: .init(style: prefs.viewerStyle, loadRemote: prefs.loadRemoteImages, customCSS: customCSS))
        }
    }

    /// A click in the preview: the same rules for notes and pages.
    private func openLink(_ url: URL) {
        if case .rendered = ws.templateState { ws.openTemplateLink(url); return }
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
        let code = ws.isCodeFile
        let words = DocumentStore.wordCount(ws.showingHTML && ws.mode == .view ? HTMLText.visible(document.text) : document.text)
        let lines = document.text.isEmpty ? 0 : document.text.split(separator: "\n", omittingEmptySubsequences: false).count
        return HStack(spacing: 2) {
            if document.url != nil {
                if code && ws.mode == .write { Text("\(lines) \(lines == 1 ? "line" : "lines")") }
                else { Text("\(words) \(words == 1 ? "word" : "words") · \(DocumentStore.readMinutes(words: words)) min read") }
            }
            let waiting = prefs.agentsEnabled ? proposals.items.filter { $0.status == .pending && $0.workspace === ws }.count : 0
            if waiting > 0 {
                Text("·").padding(.horizontal, 4)
                Button { ws.openPanel(.review) } label: { Text("\(waiting) \(waiting == 1 ? "suggestion" : "suggestions")").foregroundStyle(Color(Palette.link)) }
                    .buttonStyle(.plain).accessibilityLabel("\(waiting) suggestions waiting. Open the Review tab")
            }
            Spacer()
            if document.url != nil, !code, ws.mode == .write {
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
