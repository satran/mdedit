import SwiftUI

/// Settings: flat grouped rows like the rest of the app.
struct SettingsView: View {
    @EnvironmentObject var prefs: Preferences

    static let editorFonts = ["IBM Plex Mono", "JetBrains Mono", "SF Mono", "Menlo", "Source Serif 4"]
        static let presets: [(String, Int)] = [("Narrow", 64), ("Medium", 72), ("Wide", 80)]

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
                    row("Font") {
                        fontPicker($prefs.editorFont, Self.editorFonts, label: "Editor font")
                        stepper($prefs.editorSize, 11...28, label: "editor font size")
                    }
                    divider
                    row("Line width", note: "Characters per line") {
                        if prefs.widthCustom {
                            HStack(spacing: 6) {
                                TextField("", value: Binding(get: { prefs.lineWidth }, set: { prefs.lineWidth = min(160, max(40, $0)) }), format: .number)
                                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 56)
                                    .accessibilityLabel("Custom line width in characters")
                                Text("ch").font(.system(size: 12)).foregroundStyle(Color(Palette.muted))
                            }
                        }
                        widthPicker
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
                    row("Template", note: "Serif is Literata, sans is Inter") {
                        HStack(spacing: 2) {
                            ForEach([("serif", "Serif"), ("sans", "Sans")], id: \.0) { key, name in
                                segment(name, on: prefs.viewerTemplate == key) { prefs.viewerTemplate = key }
                            }
                        }
                        .padding(2).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.segmentTrack)))
                    }
                    divider
                    row("Text size", note: "Serif body; sans runs 2 points smaller") {
                        stepper($prefs.viewerSize, 14...28, label: "viewer text size")
                    }
                    divider
                    row("Remote pictures", note: "A picture on the web tells its server you opened the note") {
                        Toggle("Load remote pictures", isOn: $prefs.loadRemoteImages).labelsHidden().toggleStyle(.switch)
                    }
                    divider
                    viewerPreview
                }
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 24)
        }
        .frame(width: 680, height: 560)
        .background(Color(Palette.binderBg))
        .foregroundStyle(Color(Palette.binderText))
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

    private func fontPicker(_ sel: Binding<String>, _ fonts: [String], label: String) -> some View {
        Picker(label, selection: sel) {
            ForEach(fonts, id: \.self) { f in
                Text(Self.thirdParty.contains(f) && !Fonts.installed(f) ? "\(f) (not installed)" : f).tag(f)
            }
        }
        .labelsHidden().frame(width: 250)
    }

    /// Fonts that neither ship in the app nor come with macOS; the app falls back when one is missing.
    static let thirdParty: Set<String> = ["JetBrains Mono", "Literata", "Inter"]

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

    private var widthPicker: some View {
        let current = prefs.widthCustom ? nil : Self.presets.first { $0.1 == prefs.lineWidth }?.0
        return HStack(spacing: 2) {
            ForEach(Self.presets, id: \.0) { name, n in segment(name, on: current == name) { prefs.widthCustom = false; prefs.lineWidth = n } }
            segment("Custom", on: current == nil) { prefs.widthCustom = true }
        }
        .padding(2).background(RoundedRectangle(cornerRadius: 8).fill(Color(Palette.segmentTrack)))
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
