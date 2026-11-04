import SwiftUI

/// The Run tab of the side panel (⌘R): type a command, choose where its output goes, press Return. ↑↓ pick from saved scripts and recent commands.
/// What a command printed is shown under the box.
struct ShellBarView: View {
    @EnvironmentObject var ws: Workspace
    @EnvironmentObject var prefs: Preferences
    @State private var query = ""
    @State private var selected: Int?
    @FocusState private var focused: Bool

    enum Pick: Hashable { case script(String), recent(String) }

    /// Saved scripts first (all of them, up to 20), then the most recent commands (up to 8); typed words narrow both.
    static func picks(scripts: [String], history: [String], query: String) -> [Pick] {
        let words = query.lowercased().split(separator: " ")
        func hit(_ s: String) -> Bool { words.allSatisfy { s.lowercased().contains($0) } }
        return scripts.filter(hit).prefix(20).map(Pick.script) + history.reversed().filter(hit).prefix(8).map(Pick.recent)
    }

    private var picks: [Pick] { Self.picks(scripts: ws.shellScripts, history: ws.shellRecents, query: query) }

    var body: some View {
        let list = picks, running = ws.shellJob != nil
        // a command works on the note in the editor: with a page, a note in the preview or none open there is nothing to run on
        let canRun = ws.document.url != nil && ws.mode == .write
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                    TextField("Run a shell command", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                        .focused($focused).focusEffectDisabled().disabled(running || !canRun)
                        .onSubmit { submit(list) }
                        .onKeyPress(.upArrow) { move(-1, list.count); return .handled }
                        .onKeyPress(.downArrow) { move(1, list.count); return .handled }
                        .onKeyPress(.tab) { cycle(); return .handled }
                        .onExitCommand { if running { ws.cancelShell() } else { ws.closeRun() } }
                        .onChange(of: query) { _, _ in selected = nil }
                    if running {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { ws.cancelShell() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color(Palette.link)).pointerCursor()
                    }
                }
                .padding(.horizontal, 9).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.field)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Palette.binderBorder), lineWidth: 1))
                HStack(spacing: 2) {
                    ForEach(ShellDestination.allCases, id: \.self) { d in
                        Button { ws.shellDestination = d } label: {
                            Text(d.title).font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 22)
                                .background(RoundedRectangle(cornerRadius: 6).fill(ws.shellDestination == d ? Color(Palette.segmentOn) : .clear))
                                .foregroundStyle(Color(ws.shellDestination == d ? Palette.binderText : Palette.segmentText))
                        }.buttonStyle(.plain).disabled(running).pointerCursor()
                    }
                }
                .padding(2).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.segmentTrack)))
                Text(!canRun ? "Commands run on a note in Write mode."
                     : running ? "Running… ⎋ cancels" : ws.shellDestination.detail + ". The selection, or the whole note, goes in on stdin.")
                    .font(.system(size: 11.5)).foregroundStyle(Color(Palette.muted)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                if !list.isEmpty && !running && canRun {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, pick in
                            HStack(spacing: 6) {
                                switch pick {
                                case .script(let n): Image(systemName: "doc.text").font(.system(size: 11)); Text(n)
                                case .recent(let c): Image(systemName: "clock").font(.system(size: 11)); Text(c).font(.system(size: 12.5, design: .monospaced))
                                }
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 13)).lineLimit(1)
                            .foregroundStyle(Color(Palette.binderText))
                            .padding(.horizontal, 8).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 6).fill(i == selected ? Color(Palette.selection) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(i == selected ? Color(Palette.binderBorder) : .clear, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { selected = i; submit(list) }
                            .pointerCursor()
                        }
                    }
                }
                if let log = ws.shellLog { ShellLogView(log: log) { ws.shellLog = nil } }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(Palette.binderBg))
        .onAppear {
            ws.refreshShellLists(prefs: prefs)
            focused = true
        }
        .onChange(of: ws.shellFocusTick) { _, _ in focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run a shell command")
    }

    /// ↑↓ walk the suggestions; past either end goes back to the box.
    private func move(_ delta: Int, _ count: Int) {
        guard count > 0 else { selected = nil; return }
        let next = (selected ?? (delta > 0 ? -1 : count)) + delta
        selected = next < 0 || next >= count ? nil : next
    }

    private func cycle() {
        let all = ShellDestination.allCases
        ws.shellDestination = all[((all.firstIndex(of: ws.shellDestination) ?? 0) + 1) % all.count]
    }

    private func submit(_ list: [Pick]) {
        if let i = selected, list.indices.contains(i) {
            switch list[i] {
            case .script(let n): ws.runShell(.script(n), destination: ws.shellDestination, prefs: prefs)
            case .recent(let c): query = c; selected = nil          // a recent command is put in the box; Return runs it
            }
        } else {
            ws.runShell(.command(query), destination: ws.shellDestination, prefs: prefs)
        }
    }
}

/// What a command printed when it failed, or when the output was only to be shown. Sits under the box in the Run tab.
struct ShellLogView: View {
    let log: ShellLog
    let close: () -> Void

    private var text: String {
        let e = log.result.stderr, o = log.result.stdout
        return e.isEmpty || o.isEmpty ? e + o : e + "\n— output —\n" + o
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: log.result.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(Color(log.result.succeeded ? Palette.green : Palette.muted))
                VStack(alignment: .leading, spacing: 1) {
                    Text(log.command).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Text(log.result.summary + String(format: " · %.1fs", log.result.duration)).font(.system(size: 11)).foregroundStyle(Color(Palette.muted))
                }
                Spacer(minLength: 8)
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color(Palette.link)).pointerCursor()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(Color(Palette.muted)).accessibilityLabel("Close log").pointerCursor()
            }
            if let n = log.note { Text(n).font(.system(size: 11.5)).foregroundStyle(Color(Palette.muted)) }
            if log.showsOutput {
                Text(text.isEmpty ? "No output." : text)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(Palette.binderText))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.field).opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(Palette.binderBorder), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command log")
    }
}

extension View {
    /// The pointing hand over something clickable. The note under an overlay asks for an I-beam, so it is asked for twice.
    func pointerCursor() -> some View {
        onContinuousHover { phase in
            if case .active = phase {
                NSCursor.pointingHand.set()
                DispatchQueue.main.async { NSCursor.pointingHand.set() }
            }
        }
    }
}
