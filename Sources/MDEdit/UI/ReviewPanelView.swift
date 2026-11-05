import SwiftUI

/// The Review tab: one card per suggestion an agent made for this window. Nothing changes in a note until Accept.
struct ReviewPanelView: View {
    @EnvironmentObject var ws: Workspace
    @ObservedObject private var store = ProposalStore.shared

    private static let maxDiffLines = 12

    var body: some View {
        let cards = store.items.filter { $0.isOpen && $0.workspace === ws }.sorted { $0.createdAt > $1.createdAt }
        Group {
            if cards.isEmpty { empty } else {
                ScrollView {
                    VStack(spacing: 10) { ForEach(cards) { card($0) } }
                        .padding(.horizontal, 12).padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("No suggestions").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(Palette.strongText))
            Text("Suggestions from connected agents show up here, and nothing changes until you accept it.")
                .font(.system(size: 12.5)).foregroundStyle(Color(Palette.muted)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: 230).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ p: Proposal) -> some View {
        let stale = p.status == .stale, selected = ws.selectedProposal == p.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.title.isEmpty ? "Suggestion" : p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(Palette.strongText))
                Spacer(minLength: 0)
                if stale { Text("Changed since proposed").font(.system(size: 10.5)).padding(.horizontal, 8).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.25))) }
                else { Text("\(p.client) · \(age(p.createdAt))").font(.system(size: 11)).foregroundStyle(Color(Palette.muted)).lineLimit(1) }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            if !p.reason.isEmpty {
                Text(p.reason).font(.system(size: 12)).foregroundStyle(Color(Palette.muted)).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.bottom, 9)
            }
            diff(p)
            if !p.message.isEmpty {
                Text(p.message).font(.system(size: 11.5)).foregroundStyle(Color(Palette.removedInk)).padding(.horizontal, 12).padding(.top, 6)
            }
            HStack(spacing: 6) {
                if stale {
                    button("Dismiss", primary: false) { store.reject(p.id); ws.refreshSuggestionMark() }
                } else {
                    button("Reject", primary: false) { store.reject(p.id); ws.refreshSuggestionMark() }
                    button("Accept", primary: true) { Task { await store.accept(p.id); ws.refreshSuggestionMark() } }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(Palette.paneBg)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(selected ? Palette.link : Palette.binderBorder), lineWidth: selected ? 2 : 1))
        .opacity(stale ? 0.75 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { Task { await ws.showSuggestion(p.id) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestion: \(p.title)")
    }

    private func diff(_ p: Proposal) -> some View {
        VStack(spacing: 0) {
            lines(p.old, marker: "-", bg: Palette.removedBg, ink: Palette.removedInk)
            lines(p.new, marker: "+", bg: Palette.addedBg, ink: Palette.addedInk)
        }
        .overlay(alignment: .top) { Rectangle().fill(Color(Palette.paneBorder)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(Palette.paneBorder)).frame(height: 1) }
    }

    @ViewBuilder
    private func lines(_ text: String, marker: String, bg: NSColor, ink: NSColor) -> some View {
        let all = text.isEmpty ? [] : text.components(separatedBy: "\n")
        let shown = Array(all.prefix(Self.maxDiffLines))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, l in
                Text("\(marker) \(l)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color(ink))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 1)
            }
            if all.count > shown.count {
                Text("… \(all.count - shown.count) more lines").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(ink))
                    .padding(.horizontal, 12).padding(.vertical, 1)
            }
            if all.isEmpty { Text("\(marker) (nothing)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color(ink)).padding(.horizontal, 12).padding(.vertical, 1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).background(Color(bg))
    }

    private func button(_ title: String, primary: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).padding(.horizontal, 11).frame(height: 26)
                .foregroundStyle(Color(primary ? Palette.paneBg : Palette.binderText))
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(primary ? Palette.strongText : Palette.segmentTrack)))
        }
        .buttonStyle(.plain)
    }

    private func age(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        return s < 60 ? "now" : s < 3600 ? "\(s / 60) min" : "\(s / 3600) h"
    }
}
