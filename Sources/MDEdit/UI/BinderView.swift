import SwiftUI

struct BinderView: View {
    @EnvironmentObject var ws: Workspace
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // the folder's name sits in the title row, to the right of the traffic lights: small capitals, quiet
            ZStack(alignment: .leading) {
                WindowDragArea()
                if let root = ws.rootURL {
                    Text(Self.headerTitle(root))
                        .font(.system(size: 11, weight: .semibold)).tracking(0.7)
                        .foregroundStyle(Color(Palette.muted).opacity(0.8))
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.leading, Self.titleInset).padding(.trailing, 14)
                        .allowsHitTesting(false)                // a drag on the name still moves the window
                        .accessibilityLabel("Folder: \(root.lastPathComponent)")
                }
            }
            .frame(height: Metrics.headerHeight)
            searchField
            if ws.root != nil { OpenTabsView(document: ws.document) }
            if ws.root == nil { emptyState } else { tree }
            footer
        }
        .background(Color(Palette.binderBg))
        .foregroundStyle(Color(Palette.binderText))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Binder")
        .onAppear { takeFocus() }
        .onChange(of: ws.wantsSearchFocus) { _, _ in takeFocus() }
    }

    /// Asked for by Search Binder: the caret goes to the search field. The list itself takes no keys: it is used with the mouse.
    private func takeFocus() {
        if ws.wantsSearchFocus {
            ws.wantsSearchFocus = false
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    /// Room for the three traffic lights (they start 20 pt in and take about 52 pt) and a gap.
    static let titleInset: CGFloat = 92

    static func headerTitle(_ folder: URL) -> String { folder.lastPathComponent.uppercased() }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
            TextField("Search", text: $ws.search).textFieldStyle(.plain).font(.system(size: 13))
                .focused($searchFocused)
                .accessibilityLabel("Search binder")
            if !ws.search.isEmpty {
                Button { ws.search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(Color(Palette.muted)).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.field)))
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    private var tree: some View {
        let rows = ws.rows
        return ScrollViewReader { proxy in ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    BinderRowView(row: row, selected: ws.selection == row.node.url, gap: row.depth == 0 && i > 0 ? 8 : 0)
                }
                if rows.isEmpty {
                    Text(ws.search.isEmpty ? "No Markdown files here yet" : "No matches")
                        .font(.system(size: 12)).foregroundStyle(Color(Palette.muted)).padding(.top, 16)
                }
            }
            .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 12)
        }
        .onChange(of: ws.selection) { _, sel in if let sel { proxy.scrollTo(sel) } }
        }
        .frame(maxHeight: .infinity)
        // no key handling here: the list is not focusable, so arrow keys never move the selection and renaming has the keyboard to itself
        .dropDestination(for: URL.self) { urls, _ in
            guard let root = ws.rootURL else { return false }
            ws.drop(urls, into: root)
            return true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder").font(.system(size: 28, weight: .light)).foregroundStyle(Color(Palette.muted))
            Text("Open a folder of Markdown files").font(.system(size: 13)).foregroundStyle(Color(Palette.muted))
            Button("Open Folder…") { ws.chooseFolder() }.controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button { ws.newDocument() } label: {
                HStack(spacing: 6) { Image(systemName: "plus").font(.system(size: 12, weight: .medium)); Text("New Document").font(.system(size: 13, weight: .medium)) }
                    .padding(.horizontal, 8).frame(height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(ws.root == nil)
            Spacer()
            IconButton(symbol: "folder.badge.plus", label: "New folder") { ws.newFolder() }.disabled(ws.root == nil)
            Menu {
                Button("Open Folder…") { ws.chooseFolder() }
                Button("Reveal in Finder") { ws.revealInFinder() }.disabled(ws.root == nil)
                Button("Collapse All") { ws.collapseAll() }.disabled(ws.root == nil)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30).accessibilityLabel("Binder options")
        }
        .foregroundStyle(Color(Palette.muted))
        .padding(.horizontal, 8).frame(height: Metrics.footerHeight)
        .overlay(alignment: .top) { Rectangle().fill(Color(Palette.binderBorder)).frame(height: 1) }
    }
}

struct BinderRowView: View {
    @EnvironmentObject var ws: Workspace
    let row: BinderRow
    let selected: Bool
    let gap: CGFloat
    @State private var hover = false
    @State private var dropTarget = false
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        let node = row.node
        HStack(spacing: 6) {
            Group {
                if node.isFolder {
                    Image(systemName: row.isOpen ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                } else { Color.clear }
            }
            .frame(width: 12, height: 12).foregroundStyle(Color(Palette.muted))
            Image(systemName: node.symbol).font(.system(size: 12)).foregroundStyle(Color(Palette.muted)).frame(width: 16)
            if ws.renaming == node.url {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($editing)
                    .onSubmit { ws.rename(node.url, to: draft) }
                    .onExitCommand { ws.renaming = nil }
                    .onAppear {
                        draft = node.name; editing = true
                        DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                    }
                    .onChange(of: editing) { _, now in if !now, ws.renaming == node.url { ws.rename(node.url, to: draft) } }
            } else {
                Text(node.label).font(.system(size: 13, weight: row.depth == 0 && node.isFolder ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4 + CGFloat(row.depth) * Metrics.indent).padding(.trailing, 8)
        .frame(height: Metrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: 7).fill(dropTarget ? Color(Palette.link).opacity(0.18) : selected ? Color(Palette.selection) : (hover ? Color(Palette.selection).opacity(0.5) : .clear)))
        .padding(.top, gap)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { if ws.renaming == nil { ws.renaming = node.url } }
        .simultaneousGesture(TapGesture().onEnded {
            guard ws.renaming != node.url else { return }
            ws.select(node.url)
            if node.opensInApp { ws.editor.keepFocusElsewhere = false; DispatchQueue.main.async { ws.focusEditor() } }
        })
        .draggable(node.url)
        .dropDestination(for: URL.self) { urls, _ in
            // on a file, it goes into the folder that file is in
            ws.drop(urls, into: node.isFolder ? node.url : node.url.deletingLastPathComponent())
            return true
        } isTargeted: { dropTarget = $0 && node.isFolder }
        .contextMenu {
            Button("New Document Here") { ws.newDocument(in: node.isFolder ? node.url : node.url.deletingLastPathComponent()) }
            Button("New Folder Here") { ws.newFolder(in: node.isFolder ? node.url : node.url.deletingLastPathComponent()) }
            Divider()
            Button("Rename") { ws.renaming = node.url }
            if !node.isFolder && !node.opensInApp {
                // programs are shown, never started from here
                Button(LinkPolicy.isProgram(node.url) ? "Reveal Program in Finder" : "Open in Default App") {
                    if LinkPolicy.isProgram(node.url) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) } else { NSWorkspace.shared.open(node.url) }
                }
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Divider()
            Button("Move to Trash") { ws.trash(node.url) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.label)
        .accessibilityValue(node.isFolder ? (row.isOpen ? "expanded" : "collapsed") : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Rename") { ws.renaming = node.url }
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 13
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}
