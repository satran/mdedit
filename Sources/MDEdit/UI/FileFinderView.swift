import SwiftUI

/// What the finder shows: the text typed, the files that match it and the one highlighted. Kept apart from the view so a
/// test can type into it.
@MainActor
final class FileFinderModel: ObservableObject {
    struct Row: Identifiable {
        let id: Int
        let url: URL
        let name: AttributedString
        let folder: String
        /// The folder as drawn: the letters that matched in bold.
        let folderText: AttributedString
    }

    static let limit = 50
    @Published var query = "" { didSet { if oldValue != query { selected = 0; refresh() } } }
    @Published var selected = 0
    @Published private(set) var rows: [Row] = []
    private var index: FileIndex?
    private var recent: [URL] = []

    /// Called when the box opens: the files to search, and the notes opened last.
    func load(index: FileIndex?, recent: [URL]) {
        index?.forget()
        self.index = index
        self.recent = recent
        refresh()
    }

    var selectedURL: URL? { rows.indices.contains(selected) ? rows[selected].url : nil }

    func move(_ step: Int) { selected = min(max(0, rows.count - 1), max(0, selected + step)) }

    private func refresh() {
        guard let index else { rows = []; return }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            // nothing typed: the notes visited last, then the rest in path order
            var seen = Set<URL>(), picks: [Int] = []
            let byURL = Dictionary(index.entries.enumerated().map { ($1.url.standardizedFileURL, $0) }, uniquingKeysWith: { a, _ in a })
            for u in recent.reversed() {
                let s = u.standardizedFileURL
                if let i = byURL[s], seen.insert(s).inserted { picks.append(i) }
                if picks.count >= Self.limit { break }
            }
            var i = 0
            while picks.count < Self.limit, i < index.entries.count {
                if seen.insert(index.entries[i].url.standardizedFileURL).inserted { picks.append(i) }
                i += 1
            }
            rows = picks.map { row($0, index) }
        } else {
            rows = index.search(q, limit: Self.limit).map { row($0.entry, index, highlighting: q) }
        }
    }

    private func row(_ i: Int, _ index: FileIndex, highlighting q: String? = nil) -> Row {
        let e = index.entries[i]
        let hit = Set(q.map { index.positions($0, in: e) } ?? [])
        let scalars = Array(e.path.unicodeScalars)
        var name = AttributedString()
        // the file name, with the letters that matched in bold
        for (k, u) in scalars.enumerated() where k >= e.nameStart {
            var piece = AttributedString(String(u))
            if hit.contains(k) { piece.font = .system(size: 13, weight: .bold) }
            name += piece
        }
        var folder = String(String.UnicodeScalarView(scalars[..<e.nameStart]))
        var folderText = AttributedString()
        for (k, u) in scalars[..<e.nameStart].enumerated() {
            var piece = AttributedString(String(u))
            if hit.contains(k) { piece.font = .system(size: 12, weight: .bold) }
            folderText += piece
        }
        if folder.hasSuffix("/") { folder.removeLast(); folderText.characters.removeLast() }
        return Row(id: i, url: e.url, name: name, folder: folder, folderText: folderText)
    }
}

/// ⇧⌘O: type a few letters of a file's name or path and open it. The look is the command palette's.
struct FileFinderView: View {
    @EnvironmentObject var ws: Workspace
    @StateObject private var model: FileFinderModel
    @FocusState private var focused: Bool
    @State private var monitor: Any?

    @MainActor init(model: FileFinderModel? = nil) { _model = StateObject(wrappedValue: model ?? FileFinderModel()) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                TextField("Go to file", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($focused)
                    .focusEffectDisabled()
                    .onSubmit { open() }
                    .onExitCommand { ws.finderVisible = false }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(Color(Palette.muted)).accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.field)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Palette.binderBorder), lineWidth: 1))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                            HStack(spacing: 8) {
                                Text(row.name).font(.system(size: 13)).lineLimit(1).layoutPriority(1)
                                Text(row.folderText).font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                                    .lineLimit(1).truncationMode(.head)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Color(Palette.binderText))
                            .padding(.horizontal, 8).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 6).fill(i == model.selected ? Color(Palette.selection) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(i == model.selected ? Color(Palette.binderBorder) : .clear, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { model.selected = i; open() }
                        }
                        if model.rows.isEmpty {
                            Text(model.query.isEmpty ? "No files" : "No matching file").font(.system(size: 12.5))
                                .foregroundStyle(Color(Palette.muted)).padding(.vertical, 10)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: model.selected) { _, n in if model.rows.indices.contains(n) { proxy.scrollTo(model.rows[n].id) } }
            }
        }
        .padding(6)
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(Palette.binderBg)).shadow(color: .black.opacity(0.16), radius: 14, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(Palette.binderBorder), lineWidth: 1))
        .onAppear {
            model.load(index: ws.fileIndex(), recent: ws.visited + [ws.document.url].compactMap { $0 })
            focused = true
            watchKeys()
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Go to file")
    }

    private func open() {
        guard let url = model.selectedURL else { return }
        ws.goToFile(url)
    }

    /// The text field's own editor takes the arrow keys for the caret, so they are caught before it sees them.
    /// Up, Down and ⌃P, ⌃N move the highlight; the field keeps everything else.
    private func watchKeys() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model, weak ws] e in
            guard let ws, e.window === ws.hostWindow else { return e }
            let mods = e.modifierFlags.intersection([.control, .command, .option, .shift])
            let step: Int
            switch (e.keyCode, e.charactersIgnoringModifiers) {
            case (125, _) where mods.isEmpty, (_, "n") where mods == .control: step = 1
            case (126, _) where mods.isEmpty, (_, "p") where mods == .control: step = -1
            default: return e
            }
            model.move(step)
            return nil
        }
    }
}
