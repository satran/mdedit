import SwiftUI

/// A tooltip that appears when the pointer rests on the view. Set on a view behind the control so clicks still reach it.
private struct TipView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSView { let v = NSView(); v.toolTip = text; return v }
    func updateNSView(_ v: NSView, context: Context) { v.toolTip = text }
}

extension View {
    func tip(_ text: String) -> some View { background(TipView(text: text)) }
}

/// Find & replace, a tab of the right-hand panel: "This file" shows its matches as a list; "Folder" shows every note
/// with a match, each match with a box, and what it would become.
struct FindPanel: View {
    @EnvironmentObject var ws: Workspace
    @ObservedObject var find: FindModel
    @ObservedObject var document: DocumentStore
    @FocusState private var focused: FindModel.Field?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Rectangle().fill(Color(Palette.binderBorder)).frame(height: 1)
            resultsHeader
            results
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(Palette.binderBg))
        .accessibilityElement(children: .contain).accessibilityLabel("Find and replace")
        .onChange(of: document.text) { _, _ in find.refresh() }
        .onChange(of: ws.treeVersion) { _, _ in if find.scope == .folder { find.refresh() } }
        .onChange(of: document.url) { _, _ in find.refresh() }
        .onChange(of: ws.mode) { _, _ in DispatchQueue.main.async { find.highlight() } }
        .onChange(of: find.focus) { _, f in if let f { focused = f; find.focus = nil } }
        .onAppear { if let f = find.focus { focused = f; find.focus = nil } else { focused = .find } }
        .onExitCommand { ws.closeFind() }
    }

    // MARK: controls

    private var controls: some View {
        VStack(spacing: 10) {
            scopeSwitch
            if find.scope == .folder { areaMenu }
            findField
            optionRow
            replaceField
            actionRow
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
    }

    private var scopeSwitch: some View {
        HStack(spacing: 2) {
            ForEach([(FindModel.Scope.file, "This file", "doc"), (.folder, "Folder", "folder")], id: \.1) { scope, title, icon in
                Button { find.scope = scope } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon).font(.system(size: 11))
                        Text(title).font(.system(size: 12.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(find.scope == scope ? Color(Palette.segmentOn) : .clear))
                    .foregroundStyle(Color(find.scope == scope ? Palette.binderText : Palette.segmentText))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor().tip(scope == .file ? "Find and replace in the open note" : "Find and replace in every note of the folder")
                .accessibilityAddTraits(find.scope == scope ? .isSelected : [])
                .disabled(scope == .file && find.ws?.showingHTML == true)
            }
        }
        .padding(2).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.segmentTrack)))
        .accessibilityElement(children: .contain).accessibilityLabel("Search scope")
    }

    private var areaMenu: some View {
        HStack(spacing: 8) {
            Text("Search in").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
            Menu {
                Button("Whole project") { find.area = .project }
                Button("This note's folder") { find.area = .noteFolder }.disabled(document.url == nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 11))
                    Text(find.area == .project ? "Whole project" : "This note's folder").font(.system(size: 12.5)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .menuStyle(.borderlessButton).accessibilityLabel("Search in")
            .padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(Palette.paneBg)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(Palette.binderBorder), lineWidth: 1))
        }
    }

    private var findField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
            TextField("Find", text: $find.query)
                .textFieldStyle(.plain).font(.system(size: 13)).focused($focused, equals: .find)
                .onSubmit { if find.scope == .file { find.next() } }
                .accessibilityLabel("Find")
            Text(countText).font(.system(size: 12).monospacedDigit()).foregroundStyle(Color(find.problem == nil ? Palette.muted : Palette.removedInk)).lineLimit(1)
        }
        .padding(.leading, 10).padding(.trailing, 8).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.paneBg)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(focused == .find ? Palette.caret : Palette.binderBorder), lineWidth: 1))
    }

    private var countText: String {
        if let p = find.problem { return p }
        if find.query.isEmpty { return "" }
        switch find.scope {
        case .file: return find.matches.isEmpty ? "No results" : "\(find.current + 1) of \(find.matches.count)\(find.truncated ? "+" : "")"
        case .folder:
            if find.busy && find.groups.isEmpty { return "Searching…" }
            return find.groups.isEmpty ? "No results" : "\(find.totalCount)\(find.truncated ? "+" : "") in \(find.groups.count) \(find.groups.count == 1 ? "file" : "files")"
        }
    }

    private var optionRow: some View {
        HStack(spacing: 4) {
            toggle("Aa", "Match case", "Match case: “Time” does not match “time”", $find.options.matchCase)
            toggle("ab", "Whole word", "Whole word: “cat” does not match “concat”", $find.options.wholeWord, underline: true)
            toggle(".*", "Regular expression", "Regular expression: use $1, $2 … in the replacement for groups", $find.options.regex, mono: true)
            Spacer()
            if find.scope == .file {
                stepper("chevron.up", "Previous match", "Previous match (⇧⌘G)") { find.next(-1) }
                stepper("chevron.down", "Next match", "Next match (⌘G, or Return in the Find field)") { find.next(1) }
            } else {
                Button(find.allExpanded ? "Collapse all" : "Expand all") { find.toggleAllExpanded() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color(Palette.link)).disabled(find.groups.isEmpty).pointerCursor()
                    .tip(find.allExpanded ? "Fold every note's matches away" : "Show the matches of every note")
            }
        }
    }

    private func toggle(_ label: String, _ name: String, _ tip: String, _ on: Binding<Bool>, underline: Bool = false, mono: Bool = false) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Text(label).font(mono ? .system(size: 12, weight: .semibold, design: .monospaced) : .system(size: 12, weight: .semibold))
                .underline(underline, color: Color(Palette.link))
                .frame(minWidth: 30, minHeight: 26).padding(.horizontal, 6)
                .foregroundStyle(Color(on.wrappedValue ? Palette.link : Palette.segmentText))
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(on.wrappedValue ? Palette.selection : Palette.paneBg)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(on.wrappedValue ? Palette.caret : Palette.binderBorder), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).tip(tip).accessibilityLabel(name).accessibilityAddTraits(on.wrappedValue ? .isSelected : []).pointerCursor()
    }

    private func stepper(_ symbol: String, _ name: String, _ tip: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 28, height: 26)
                .foregroundStyle(Color(Palette.segmentText))
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(Palette.paneBg)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(Palette.binderBorder), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).tip(tip).accessibilityLabel(name).disabled(find.matches.isEmpty).pointerCursor()
    }

    private var replaceField: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 11)).foregroundStyle(Color(Palette.muted))
            TextField("Replace with", text: $find.replacement)
                .textFieldStyle(.plain).font(.system(size: 13)).focused($focused, equals: .replace)
                .onSubmit { if find.scope == .file { find.replaceCurrent() } }
                .accessibilityLabel("Replace with")
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.paneBg)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(focused == .replace ? Palette.caret : Palette.binderBorder), lineWidth: 1))
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Toggle("Preserve case", isOn: $find.options.preserveCase).toggleStyle(.checkbox).font(.system(size: 12)).foregroundStyle(Color(Palette.segmentText))
                .tip("Preserve case: “Time” becomes “Failed”, “time” becomes “failed”, “TIME” becomes “FAILED”")
            Spacer(minLength: 4)
            if find.scope == .file {
                button("Replace", primary: false, tip: "Replace the current match and go to the next (Return in the Replace field)") { find.replaceCurrent() }.disabled(find.matches.isEmpty)
                button("Replace all", primary: true, tip: "Replace every match in this note. One Undo takes it back") { find.replaceAllInFile() }.disabled(find.matches.isEmpty)
            } else {
                button(find.selectedCount == 0 ? "Replace" : "Replace \(find.selectedCount) in \(find.selectedFiles) \(find.selectedFiles == 1 ? "file" : "files")", primary: true, tip: "Replace the ticked matches in every note. ⌘Z takes it back") { find.replaceSelected() }
                    .disabled(find.selectedCount == 0)
            }
        }
    }

    private func button(_ title: String, primary: Bool, tip: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: primary ? .semibold : .medium)).lineLimit(1)
                .padding(.horizontal, 12).frame(height: 28)
                .foregroundStyle(primary ? Color.white : Color(Palette.binderText))
                .background(RoundedRectangle(cornerRadius: 7).fill(primary ? Color(Palette.caret) : Color(Palette.paneBg)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(primary ? .clear : Color(Palette.binderBorder), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor().tip(tip)
    }

    // MARK: results

    private var resultsHeader: some View {
        HStack {
            Text("Results").font(.system(size: 11, weight: .semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(Color(Palette.muted))
            Spacer()
            if find.scope == .folder, !find.groups.isEmpty {
                Text("\(find.selectedCount) of \(find.totalCount) selected").font(.system(size: 11.5)).foregroundStyle(Color(Palette.muted))
            } else if find.scope == .file, !find.matches.isEmpty {
                Text(find.matches.count == 1 ? "1 match" : "\(find.matches.count) matches").font(.system(size: 11.5)).foregroundStyle(Color(Palette.muted))
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
    }

    @ViewBuilder private var results: some View {
        if find.scope == .file {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(find.matches.enumerated()), id: \.offset) { i, m in
                            fileRow(i, m).id(i)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 8)
                }
                .onChange(of: find.current) { _, i in withAnimation(.none) { proxy.scrollTo(i) } }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(find.groups) { g in
                        groupHeader(g)
                        if find.expanded.contains(g.url) { ForEach(g.matches) { m in folderRow(g, m) } }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
    }

    /// The line around a match, the same in both views: the word on yellow while Replace is empty, otherwise the old text
    /// struck through in red and what it becomes in green.
    private func marked(_ m: FindMatch) -> Text { Text(Self.lineText(m, replacement: find.replacement)) }

    static func lineText(_ m: FindMatch, replacement: String) -> AttributedString {
        var out = AttributedString(m.before)
        var hit = AttributedString(m.text)
        if replacement.isEmpty {
            hit.backgroundColor = Color(Palette.findCurrent)
            out += hit
        } else {
            hit.backgroundColor = Color(Palette.removedBg); hit.foregroundColor = Color(Palette.removedInk); hit.strikethroughStyle = .single
            var add = AttributedString(m.replacement)
            add.backgroundColor = Color(Palette.addedBg); add.foregroundColor = Color(Palette.addedInk)
            out += hit; out += add
        }
        return out + AttributedString(m.after)
    }

    private func lineNumber(_ m: FindMatch) -> some View {
        Text("\(m.line)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(Palette.muted)).frame(minWidth: 20, alignment: .trailing)
    }

    private func fileRow(_ i: Int, _ m: FindMatch) -> some View {
        Button { find.current = i; find.highlight(); ws.jump(to: m.range.location, length: m.range.length) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                lineNumber(m)
                marked(m).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(Color(Palette.binderText)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(i == find.current ? Color(Palette.selection) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerCursor().tip("Go to line \(m.line)").accessibilityLabel("Line \(m.line): \(m.before)\(m.text)\(m.after)")
    }

    private func check(_ state: Int, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: state == 2 ? "checkmark.square.fill" : state == 1 ? "minus.square.fill" : "square").font(.system(size: 13))
                .foregroundStyle(Color(state == 0 ? Palette.muted : Palette.caret))
        }
        .buttonStyle(.plain).tip(state == 2 ? "Untick to leave this out of the replace" : "Tick to include in the replace")
        .accessibilityLabel(name).accessibilityValue(state == 2 ? "on" : state == 1 ? "some" : "off").pointerCursor()
    }

    private func groupHeader(_ g: FileHits) -> some View {
        let open = find.expanded.contains(g.url)
        return HStack(spacing: 6) {
            Button { if open { find.expanded.remove(g.url) } else { find.expanded.insert(g.url) } } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).frame(width: 14, height: 24)
                    .foregroundStyle(Color(Palette.muted)).contentShape(Rectangle())
            }.buttonStyle(.plain).tip(open ? "Fold the matches of \(g.name) away" : "Show the matches of \(g.name)").accessibilityLabel(open ? "Collapse \(g.name)" : "Expand \(g.name)").pointerCursor()
            check(find.fileState(g), "Include \(g.name)") { find.toggleFile(g) }
            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(Color(Palette.muted))
            (Text(g.name).fontWeight(.semibold) + (g.folder.isEmpty ? Text("") : Text("  · \(g.folder)").foregroundColor(Color(Palette.marker))))
                .font(.system(size: 12.5)).foregroundStyle(Color(Palette.binderText)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(g.matches.count)\(g.truncated ? "+" : "")").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(Palette.segmentText))
                .padding(.horizontal, 6).padding(.vertical, 1).frame(minWidth: 18)
                .background(Capsule().fill(Color(Palette.segmentTrack)))
        }
        .frame(height: 30).padding(.leading, 4).padding(.trailing, 8).padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    private func folderRow(_ g: FileHits, _ m: FindMatch) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            check(find.isOn(g.url, m) ? 2 : 0, "Include line \(m.line)") { find.toggle(g.url, m) }.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            lineNumber(m)
            marked(m).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(Color(find.isOn(g.url, m) ? Palette.binderText : Palette.muted)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 26).padding(.trailing, 8).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { find.open(g.url, m) }
        .pointerCursor().tip("Open \(g.name) at line \(m.line)")
        .accessibilityLabel("\(g.name), line \(m.line): \(m.before)\(m.text)\(m.after)")
    }

    // MARK: footer

    /// What the last replace did, or a reminder about replacing across files. Nothing shows when there is nothing to say.
    @ViewBuilder private var footer: some View {
        if find.note != nil || find.scope == .folder {
            HStack(spacing: 8) {
                if let n = find.note {
                    Image(systemName: "checkmark.circle").font(.system(size: 11)).foregroundStyle(Color(Palette.green))
                    Text(n).lineLimit(2).font(.system(size: 11.5))
                    Spacer(minLength: 4)
                    if find.canUndo { Button("Undo") { find.undoLast() }.buttonStyle(.plain).foregroundStyle(Color(Palette.link)).pointerCursor().tip("Take the replace back (⌘Z)") }
                } else {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 11))
                    Text("A replace across files can be undone with ⌘Z").lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 34)
            .overlay(alignment: .top) { Rectangle().fill(Color(Palette.paneBorder)).frame(height: 1) }
        }
    }
}
