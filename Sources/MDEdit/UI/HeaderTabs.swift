import SwiftUI

/// The colours of the tab strip in one place: light or dark is decided here, not in the views.
private struct TabStyle {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    var trackFill: Color { dark ? .white.opacity(0.07) : .black.opacity(0.05) }
    var trackEdge: Color { .primary.opacity(dark ? 0.16 : 0.10) }
    var activeFill: Color { dark ? .white.opacity(0.16) : .white }
    var activeEdge: Color { .primary.opacity(dark ? 0.22 : 0.16) }
    var hoverFill: Color { .primary.opacity(0.06) }
    var separator: Color { .primary.opacity(0.18) }
}

private extension View {
    /// Lowercase text carries its weight below the middle of its line box, so next to an icon it looks low.
    /// Lifting it a point makes the two look centred together.
    func opticallyCentred() -> some View { offset(y: -1) }
}

/// The open notes as tabs in the header, between Back and the Preview button. The strip is as wide as its tabs, like
/// Safari's: it grows with each tab until it fills the header, then the tabs shrink (down to `minTab`), then it scrolls.
/// This view only draws what `Workspace` says (see Workspace+Tabs.swift): the list, the active tab, names and numbers.
struct HeaderTabs: View {
    @EnvironmentObject var ws: Workspace
    @ObservedObject var document: DocumentStore
    @Environment(\.colorScheme) private var scheme

    static let height: CGFloat = 32, minTab: CGFloat = 130, maxTab: CGFloat = 200, gap: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let n = CGFloat(max(1, ws.openTabs.count))
            let tab = min(Self.maxTab, max(Self.minTab, (geo.size.width - Self.gap * (n - 1)) / n))
            let strip = min(geo.size.width, n * tab + Self.gap * (n - 1))
            track(tabWidth: tab)
                .frame(width: strip)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open notes")
    }

    private func track(tabWidth: CGFloat) -> some View {
        let style = TabStyle(scheme)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(ws.openTabs.enumerated()), id: \.element) { i, url in
                        HeaderTab(url: url, active: ws.activeTab == url, conflict: ws.activeTab == url && document.changedOnDisk)
                            .frame(width: tabWidth, height: Self.height).id(url)
                        if i < ws.openTabs.count - 1 { separator(after: i, style) }
                    }
                }
            }
            .onChange(of: ws.activeTab) { _, new in if let new { withAnimation { proxy.scrollTo(new) } } }
        }
        .frame(height: Self.height)
        .background(Capsule().fill(style.trackFill))
        .overlay(Capsule().stroke(style.trackEdge, lineWidth: 1))
        .clipShape(Capsule())
    }

    /// A hairline between two tabs, hidden beside the active one so its pill stays clean.
    private func separator(after i: Int, _ style: TabStyle) -> some View {
        let beside = ws.activeTab == ws.openTabs[i] || ws.activeTab == ws.openTabs[i + 1]
        return Rectangle().fill(beside ? .clear : style.separator).frame(width: 1, height: 14).frame(width: Self.gap)
    }
}

/// One tab: a × at the left under the pointer, icon and name centred, the shortcut at the right.
struct HeaderTab: View {
    @EnvironmentObject var ws: Workspace
    let url: URL
    let active: Bool
    let conflict: Bool
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let title = ws.tabTitle(url), style = TabStyle(scheme)
        ZStack {
            label(title)
            HStack {
                if hover { closeButton(title) }
                Spacer(minLength: 0)
                trailingMark
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(active ? style.activeFill : hover ? style.hoverFill : .clear))
        // inside the pill: a line centred on the edge would lose its outer half where the pill meets the track's top and bottom
        .overlay(Capsule().strokeBorder(active ? style.activeEdge : .clear, lineWidth: 1))
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture { ws.show(url) }
        .draggable(url)
        .dropDestination(for: URL.self) { urls, _ in
            guard let moved = urls.first, ws.isOpenTab(moved) else { return false }
            ws.moveTab(moved, before: url)
            return true
        }
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ws.tabFolder(url).map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Close") { close() }
    }

    /// The icon says what kind of file it is, so the name leaves the extension out, as the binder does.
    private func label(_ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ws.root?.find(url)?.symbol ?? "doc.text").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
            Text(title).font(.system(size: 13)).opticallyCentred().lineLimit(1).truncationMode(.tail).layoutPriority(1)
                .foregroundStyle(Color(active ? Palette.binderText : Palette.muted))
            if let folder = ws.tabFolder(url) {
                Text(folder).font(.system(size: 11)).opticallyCentred().foregroundStyle(Color(Palette.muted).opacity(0.8))
                    .lineLimit(1).truncationMode(.head)
            }
        }
        .padding(.horizontal, 34)
    }

    private func closeButton(_ title: String) -> some View {
        Button { close() } label: {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18).contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(Color(Palette.muted))
        .accessibilityLabel("Close \(title)").help("Close tab")
    }

    /// A changed-on-disk warning outranks the shortcut: the banner above the note asks what to do.
    @ViewBuilder private var trailingMark: some View {
        if conflict {
            Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).accessibilityLabel("Changed on disk")
        } else if let n = ws.tabNumber(url) {
            Text("⌘\(n)").font(.system(size: 12)).opticallyCentred().foregroundStyle(Color(Palette.muted).opacity(0.8))
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Close") { close() }
        Button("Close Others") { ws.closeOtherTabs(than: url) }.disabled(!ws.showsTabs)
        Button("Close Tabs to the Right") { ws.closeTabs(below: url) }.disabled(ws.openTabs.last.map { Workspace.isSame($0, url) } ?? true)
        Divider()
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func close() {
        ws.closeTab(url)
        if active { ws.focusEditor() }
    }
}
