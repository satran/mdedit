import SwiftUI

/// The notes open as tabs, above the folder's tree: click to switch, × to close, drag to reorder.
struct OpenTabsView: View {
    @EnvironmentObject var ws: Workspace
    @ObservedObject var document: DocumentStore
    static let maxRows = 8

    var body: some View {
        let tabs = ws.openTabs
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                label("OPEN")
                Spacer()
                Button { ws.newDocument() } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .medium)).frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Color(Palette.muted)).disabled(ws.root == nil)
                .accessibilityLabel("New document").help("New document")
            }
            .padding(.leading, 14).padding(.trailing, 10)
            if tabs.isEmpty {
                Text("No open notes").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                    .padding(.leading, 14).frame(height: Metrics.rowHeight, alignment: .leading)
            } else {
                // up to eight rows, then the list scrolls on its own so the tree below keeps its room
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tabs, id: \.self) { OpenTabRow(url: $0, active: ws.activeTab == $0, conflict: ws.activeTab == $0 && document.changedOnDisk) }
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: CGFloat(min(tabs.count, Self.maxRows)) * Metrics.rowHeight)
            }
            Rectangle().fill(Color(Palette.binderBorder)).frame(height: 1).padding(.top, 8).padding(.horizontal, 12)
            label("FILES").padding(.leading, 14).padding(.top, 8).padding(.bottom, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open notes")
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).tracking(0.7).foregroundStyle(Color(Palette.muted).opacity(0.8))
    }
}

struct OpenTabRow: View {
    @EnvironmentObject var ws: Workspace
    let url: URL
    let active: Bool
    let conflict: Bool
    @State private var hover = false

    var body: some View {
        let title = ws.tabTitle(url), folder = ws.tabFolder(url)
        HStack(spacing: 6) {
            Image(systemName: ws.root?.find(url)?.symbol ?? "doc.text").font(.system(size: 12))
                .foregroundStyle(Color(Palette.muted)).frame(width: 16)
            Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.tail).layoutPriority(1)
            if let folder { Text(folder).font(.system(size: 11)).foregroundStyle(Color(Palette.muted)).lineLimit(1).truncationMode(.head) }
            Spacer(minLength: 0)
            if conflict && !hover {
                // the file changed on disk under the open note: the banner above the editor asks what to do
                Image(systemName: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange).accessibilityLabel("Changed on disk")
            } else {
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Color(Palette.muted))
                .opacity(hover || active ? 1 : 0)
                .accessibilityLabel("Close \(title)").help("Close tab")
            }
        }
        .padding(.leading, 4).padding(.trailing, 6)
        .frame(height: Metrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color(Palette.selection) : hover ? Color(Palette.selection).opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            ws.reveal(url); ws.select(url)
            ws.editor.keepFocusElsewhere = false
            DispatchQueue.main.async { ws.focusEditor() }
        }
        .draggable(url)
        .dropDestination(for: URL.self) { urls, _ in
            guard let moved = urls.first, ws.isOpenTab(moved) else { return false }
            ws.moveTab(moved, before: url)
            return true
        }
        .contextMenu {
            Button("Close") { close() }
            Button("Close Others") { ws.closeOtherTabs(than: url) }.disabled(ws.openTabs.count < 2)
            Button("Close Tabs Below") { ws.closeTabs(below: url) }.disabled(ws.openTabs.last.map { Workspace.isSame($0, url) } ?? true)
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Close") { close() }
    }

    private func close() {
        ws.closeTab(url)
        if active { ws.focusEditor() }
    }
}
