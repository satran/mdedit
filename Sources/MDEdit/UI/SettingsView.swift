import SwiftUI

/// Settings: flat grouped rows like the rest of the app.
struct SettingsView: View {
    @EnvironmentObject var prefs: Preferences

    static let presets: [(String, Int)] = [("Narrow", 64), ("Medium", 72), ("Wide", 80)]
    /// The viewer's middle is the specs' column, about 68 characters.
    static let viewerPresets: [(String, Int)] = [("Narrow", 58), ("Medium", ViewerStyle.specWidth), ("Wide", 80)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Appearance") {
                    row("Theme", note: "Auto follows the system") {
                        HStack(spacing: 2) {
                            ForEach([("auto", "Auto"), ("light", "Light"), ("dark", "Dark")], id: \.0) { key, name in
                                segment(name, on: prefs.theme == key) { prefs.theme = key }
                            }
                        }
                        .padding(2).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.segmentTrack)))
                    }
                }
                section("Editor") {
                    row("Font", note: "Monospaced fonts installed on this Mac") {
                        fontPicker($prefs.editorFont, Fonts.monospacedFamilies, label: "Editor font")
                        stepper($prefs.editorSize, Preferences.editorSizeRange, label: "editor font size")
                    }
                    divider
                    row("Line width", note: "Characters per line") {
                        widthControl($prefs.lineWidth, custom: $prefs.widthCustom, presets: Self.presets, range: Preferences.editorWidthRange, label: "editor")
                    }
                    divider
                    row("Heading sizes", note: "Larger text for headings") {
                        Toggle("Heading sizes", isOn: $prefs.headingSizes).labelsHidden().toggleStyle(.switch)
                    }
                    divider
                    row("Distraction free in full screen", note: "Off keeps it in the window") {
                        Toggle("Distraction free in full screen", isOn: $prefs.focusFullScreen).labelsHidden().toggleStyle(.switch)
                    }
                    divider
                    preview
                }
                section("Viewer") {
                    row("Font", note: "Sans and serif fonts installed on this Mac. Inter is the default. The custom stylesheet can override it") {
                        fontPicker($prefs.viewerFont, Fonts.readingFamilies, label: "Viewer font")
                    }
                    divider
                    row("Text size", note: "Body size in points") {
                        stepper($prefs.viewerSize, Preferences.viewerSizeRange, label: "viewer text size")
                    }
                    divider
                    row("Line width", note: "Characters per line") {
                        widthControl($prefs.viewerWidth, custom: $prefs.viewerWidthCustom, presets: Self.viewerPresets, range: Preferences.viewerWidthRange, label: "viewer")
                    }
                    divider
                    row("Remote pictures and styles", note: "A picture or stylesheet on the web tells its server you opened the note. Scripts never run") {
                        Toggle("Load remote pictures and stylesheets", isOn: $prefs.loadRemoteImages).labelsHidden().toggleStyle(.switch)
                    }
                    divider
                    row("Custom stylesheet", note: "View ▸ Edit Preview Stylesheet creates .mdedit/preview.css in the open folder; it styles the preview of notes") {
                        EmptyView()
                    }
                    divider
                    viewerPreview
                }
                agentsSection
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 24)
        }
        .frame(width: 680, height: 560)
        .background(Color(Palette.binderBg))
        .foregroundStyle(Color(Palette.binderText))
    }

    // MARK: agent access

    @ObservedObject private var agent = AgentServerController.shared

    private var agentsSection: some View {
        section("Agents") {
            row("Agent access", note: "Lets an agent such as Claude Code read what you are editing and suggest changes. Nothing changes until you press Accept") {
                Toggle("Agent access", isOn: $prefs.agentsEnabled).labelsHidden().toggleStyle(.switch)
            }
            if prefs.agentsEnabled {
                divider
                row("Port", note: agent.statusText) {
                    TextField("", value: Binding(get: { prefs.agentPort }, set: { prefs.agentPort = min(Preferences.agentPortRange.upperBound, max(Preferences.agentPortRange.lowerBound, $0)) }), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 80).accessibilityLabel("Agent access port")
                }
                divider
                row("Token", note: "Anyone who can read this app's settings can use the token. It keeps out web pages and other users, not other software running as you. An agent with the token can read every note in the open folder") {
                    HStack(spacing: 8) {
                        Text(String(repeating: "•", count: 12)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(Palette.muted))
                        Button("Copy command") { copyConnectCommand() }
                        Button("Regenerate") { prefs.regenerateAgentToken() }
                    }
                }
                divider
                Text("Copy command puts the token on the clipboard inside a claude mcp add line, so it also lands in your shell history. Regenerate signs every agent out.")
                    .font(.system(size: 11.5)).foregroundStyle(Color(Palette.muted)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 10)
            }
        }
    }

    private func copyConnectCommand() {
        let cmd = "claude mcp add --transport http mdedit http://127.0.0.1:\(prefs.agentPort)/mcp --header \"Authorization: Bearer \(prefs.agentToken)\""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
    }

    // MARK: pieces

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(Palette.muted)).padding(.leading, 4)
            VStack(spacing: 0, content: content)
                .background(Color(Palette.paneBg))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(Palette.binderBorder)))
        }
    }

    private var divider: some View { Rectangle().fill(Color(Palette.paneBorder)).frame(height: 1) }

    private func row<C: View>(_ title: String, note: String? = nil, @ViewBuilder _ trailing: () -> C) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(Color(Palette.muted)) }
            }
            Spacer()
            trailing()
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 8).frame(minHeight: 48)
    }

    /// The fonts a picker offers: the installed ones, with the saved choice added in front when it is not among them.
    static func choices(_ fonts: [String], keeping saved: String) -> [String] { fonts.contains(saved) ? fonts : [saved] + fonts }

    private func fontPicker(_ sel: Binding<String>, _ fonts: [String], label: String) -> some View {
        // the saved font stays in the list even when it is not one of these (an old choice, or a font taken off the Mac)
        let all = Self.choices(fonts, keeping: sel.wrappedValue)
        return Picker(label, selection: sel) {
            ForEach(all, id: \.self) { f in Text(Fonts.installed(f) ? f : "\(f) (not installed)").tag(f) }
        }
        .labelsHidden().frame(width: 250)
    }

    private func stepper(_ v: Binding<Double>, _ range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 0) {
            Button { v.wrappedValue = max(range.lowerBound, v.wrappedValue - 1) } label: { Text("−").frame(width: 28, height: 26) }
                .accessibilityLabel("Decrease \(label)")
            Text("\(Int(v.wrappedValue)) pt").font(.system(size: 13)).monospacedDigit().frame(minWidth: 46)
                .overlay(alignment: .leading) { Rectangle().fill(Color(Palette.paneBorder)).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(Color(Palette.paneBorder)).frame(width: 1) }
            Button { v.wrappedValue = min(range.upperBound, v.wrappedValue + 1) } label: { Text("+").frame(width: 28, height: 26) }
                .accessibilityLabel("Increase \(label)")
        }
        .buttonStyle(.plain).font(.system(size: 15)).foregroundStyle(Color(Palette.quoteText))
        .frame(height: 28)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(Palette.rule)))
    }

    /// Narrow, Medium, Wide or a number typed in: the same control for the editor and the viewer.
    private func widthControl(_ value: Binding<Int>, custom: Binding<Bool>, presets: [(String, Int)], range: ClosedRange<Int>, label: String) -> some View {
        let current = custom.wrappedValue ? nil : presets.first { $0.1 == value.wrappedValue }?.0
        return HStack(spacing: 10) {
            if custom.wrappedValue {
                HStack(spacing: 6) {
                    TextField("", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }), format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 56)
                        .accessibilityLabel("Custom \(label) line width in characters")
                    Text("ch").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                }
            }
            HStack(spacing: 2) {
                ForEach(presets, id: \.0) { name, n in segment(name, on: current == name) { custom.wrappedValue = false; value.wrappedValue = n } }
                segment("Custom", on: current == nil) { custom.wrappedValue = true }
            }
            .padding(2).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.segmentTrack)))
        }
    }

    private func segment(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 10).frame(minWidth: 44, minHeight: 26)
                .foregroundStyle(Color(on ? Palette.strongText : Palette.segmentText))
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color(Palette.segmentOn) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PREVIEW").font(.system(size: 11, weight: .semibold)).tracking(0.3).foregroundStyle(Color(Palette.muted)).padding(.bottom, 8)
            (Text("## ").foregroundColor(Color(Palette.marker)) + Text("Two acronyms").bold() + Text(", one ") + Text("*").foregroundColor(Color(Palette.marker)) + Text("question").italic() + Text("*").foregroundColor(Color(Palette.marker)))
                .font(prefs.monoFont(CGFloat(prefs.editorSize))).lineLimit(1)
            let pct = Double(prefs.lineWidth - 40) / 120
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(Palette.segmentTrack))
                    Capsule().fill(Color(Palette.caret)).frame(width: max(8, g.size.width * pct))
                }
            }
            .frame(height: 4).padding(.top, 10)
            Text("\(prefs.lineWidth) characters per line").font(.system(size: 11.5)).foregroundStyle(Color(Palette.muted)).padding(.top, 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Palette.binderBg).opacity(0.5))
    }

    private var viewerPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREVIEW").font(.system(size: 11, weight: .semibold)).tracking(0.3).foregroundStyle(Color(Palette.muted))
            Text("Both are about the same thing: how well your systems hold up when something goes wrong.")
                .font(prefs.viewerStyle.font(prefs.viewerStyle.body)).foregroundStyle(Color(prefs.viewerStyle.ink))
                .lineSpacing(prefs.viewerStyle.lineSpacing(size: prefs.viewerStyle.body, leading: prefs.viewerStyle.bodyLeading)).lineLimit(3)
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Palette.binderBg).opacity(0.5))
    }
}
