import SwiftUI

/// A tab of the right-hand panel: the headings of the open note, and the notes that link to it.
struct OutlineView: View {
    @EnvironmentObject var ws: Workspace
    @ObservedObject var document: DocumentStore

    var body: some View {
        let headings = Outline.headings(in: document.text)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Headings") {
                    if headings.isEmpty { empty("No headings") }
                    ForEach(headings) { h in
                        Button { ws.jump(to: h.location) } label: {
                            Text(h.title).font(.system(size: 12.5, weight: h.level == 1 ? .semibold : .regular))
                                .foregroundStyle(Color(h.level <= 2 ? Palette.binderText : Palette.muted))
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .padding(.leading, CGFloat(max(0, h.level - 1)) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Heading level \(h.level): \(h.title)")
                    }
                }
                section("Linked mentions") {
                    if ws.backlinks.isEmpty { empty("No notes link here") }
                    ForEach(ws.backlinks, id: \.self) { u in
                        Button { ws.reveal(u); ws.select(u) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(Color(Palette.muted))
                                Text(u.deletingPathExtension().lastPathComponent).font(.system(size: 12.5)).lineLimit(1)
                                    .foregroundStyle(Color(Palette.link))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(Palette.binderBg))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(Palette.muted)).padding(.bottom, 4)
            content()
        }
        .accessibilityElement(children: .contain)
    }

    private func empty(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(Color(Palette.marker))
    }
}
