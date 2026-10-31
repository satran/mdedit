import SwiftUI

struct BinderView: View {
    @EnvironmentObject var ws: Workspace

    var body: some View {
        VStack(spacing: 0) {
            WindowDragArea().frame(height: Metrics.headerHeight)
            searchField
            if ws.root == nil { emptyState } else { tree }
            footer
        }
        .background(Color(Palette.binderBg))
        .foregroundStyle(Color(Palette.binderText))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Binder")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
            TextField("Search", text: $ws.search).textFieldStyle(.plain).font(.system(size: 13))
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
        return ScrollView {
            LazyVStack(spacing: 1) {
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
        .frame(maxHeight: .infinity)
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
        .padding(.horizontal, 8).frame(height: 44)
        .overlay(alignment: .top) { Rectangle().fill(Color(Palette.binderBorder)).frame(height: 1) }
    }
}

struct BinderRowView: View {
    @EnvironmentObject var ws: Workspace
    let row: BinderRow
    let selected: Bool
    let gap: CGFloat
    @State private var hover = false

    var body: some View {
        let node = row.node
        HStack(spacing: 6) {
            Group {
                if node.isFolder {
                    Image(systemName: row.isOpen ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                } else { Color.clear }
            }
            .frame(width: 12, height: 12).foregroundStyle(Color(Palette.muted))
            Image(systemName: node.isFolder ? "folder" : "doc.text").font(.system(size: 12)).foregroundStyle(Color(Palette.muted)).frame(width: 16)
            Text(node.name).font(.system(size: 13, weight: row.depth == 0 && node.isFolder ? .semibold : .regular))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4 + CGFloat(row.depth) * Metrics.indent).padding(.trailing, 8)
        .frame(height: Metrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color(Palette.selection) : (hover ? Color(Palette.selection).opacity(0.5) : .clear)))
        .padding(.top, gap)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { ws.select(node.url) }
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.name)
        .accessibilityValue(node.isFolder ? (row.isOpen ? "expanded" : "collapsed") : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
