import SwiftUI

/// The right-hand panel: the outline or find & replace, chosen with the two icons at the top. One width for both, and a
/// handle on its left edge to drag it wider or narrower.
struct RightPanelView: View {
    @EnvironmentObject var ws: Workspace
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var document: DocumentStore
    @State private var dragStart: CGFloat?

    var body: some View {
        let tab = ws.panelOnScreen ?? .outline
        HStack(spacing: 0) {
            handle
            VStack(spacing: 0) {
                header(tab)
                Rectangle().fill(Color(Palette.binderBorder)).frame(height: 1)
                switch tab {
                case .find: FindPanel(find: ws.find, document: document)
                case .outline: OutlineView(document: document)
                case .run: ShellBarView()
                }
            }
            .frame(width: ws.panelWidth)
            .background(Color(Palette.binderBg))
        }
    }

    private func header(_ tab: Workspace.RightPanel) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                item(.outline, "list.bullet.indent", "Outline", tip: "Outline (⌥⌘O)", on: tab == .outline)
                item(.find, "magnifyingglass", "Find and replace", tip: "Find and replace (⌘F)", on: tab == .find)
                // shown once the feature is on in Settings (⌘R says so when it is not)
                if prefs.shellEnabled || tab == .run { item(.run, "terminal", "Run a shell command", tip: "Run a shell command (⌘R)", on: tab == .run) }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.segmentTrack)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Panel")
            Text(tab == .find ? "Find & Replace" : tab == .run ? "Run" : "Outline")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(Palette.strongText)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: Metrics.headerHeight)
        .background(WindowDragArea())
    }

    private func item(_ tab: Workspace.RightPanel, _ symbol: String, _ label: String, tip: String, on: Bool) -> some View {
        Button { ws.selectPanel(tab) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .regular))
                .frame(width: 38, height: 26)
                .foregroundStyle(Color(on ? Palette.strongText : Palette.segmentText))
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color(Palette.segmentOn) : .clear)
                    .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityAddTraits(on ? .isSelected : [])
        .help(tip)
    }

    /// A 1pt line with a wider strip to grab, like the binder's.
    private var handle: some View {
        Rectangle().fill(Color(Palette.binderBorder)).frame(width: 1)
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            if dragStart == nil { dragStart = ws.panelWidth }
                            ws.panelWidth = ws.clampedPanelWidth((dragStart ?? ws.panelWidth) - v.translation.width)
                        }
                        .onEnded { _ in dragStart = nil })
                    .accessibilityHidden(true)
            }
    }
}
