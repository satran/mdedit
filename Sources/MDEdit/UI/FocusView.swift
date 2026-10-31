import SwiftUI

/// Distraction-free writing: one column, the current paragraph in full colour, `Esc` to leave.
struct FocusView: View {
    @EnvironmentObject var ws: Workspace
    @EnvironmentObject var prefs: Preferences
    @ObservedObject var document: DocumentStore

    var body: some View {
        ZStack {
            Color(Palette.paneBg)
            MarkdownTextEditor(text: $document.text, documentID: document.url,
                               style: EditorStyle(fontName: prefs.editorFont, size: CGFloat(prefs.editorSize) + 2, lineWidth: 72, headingSizes: prefs.headingSizes),
                               onOpenWiki: { ws.openWiki($0) },
                               wikiResolves: { ws.wikiResolves($0) }, wikiNames: { ws.index.names },
                               linksVersion: ws.treeVersion, typewriter: true, focusDim: true, bridge: ws.editor,
                               onEscape: { ws.toggleFocus(); return true },
                               dropText: { ws.linkText(forDropped: $0) })
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22)], startPoint: .top, endPoint: .bottom))
            VStack {
                HStack {
                    Spacer()
                    Button { ws.toggleFocus() } label: {
                        HStack(spacing: 8) {
                            Text("Exit")
                            Text("esc").font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(Palette.rule)))
                        }
                        .font(.system(size: 12.5)).foregroundStyle(Color(Palette.muted))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Exit distraction free writing")
                }
                .padding(.top, 24).padding(.trailing, 28)
                Spacer()
                let words = DocumentStore.wordCount(document.text)
                Text("Typewriter · 72 characters · \(words) \(words == 1 ? "word" : "words")")
                    .font(.system(size: 12)).foregroundStyle(Color(Palette.muted)).padding(.bottom, 26)
            }
        }
        .ignoresSafeArea()
    }
}
