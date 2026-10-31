import SwiftUI

/// What Settings changes. Fonts fall back when a family is not installed.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    @Published var editorFont: String { didSet { d.set(editorFont, forKey: "editorFont") } }
    @Published var editorSize: Double { didSet { d.set(editorSize, forKey: "editorSize") } }
    /// Characters per line in the editor.
    @Published var lineWidth: Int { didSet { d.set(lineWidth, forKey: "lineWidth") } }
    /// The "Custom" width is picked, even if its number happens to match a preset.
    @Published var widthCustom: Bool { didSet { d.set(widthCustom, forKey: "widthCustom") } }
    /// Headings in the editor are larger than body text; off keeps them the body size (still bold).
    @Published var headingSizes: Bool { didSet { d.set(headingSizes, forKey: "headingSizes") } }
    @Published var showStatusBar: Bool { didSet { d.set(showStatusBar, forKey: "showStatusBar") } }
    @Published var viewerFont: String { didSet { d.set(viewerFont, forKey: "viewerFont") } }
    @Published var viewerSize: Double { didSet { d.set(viewerSize, forKey: "viewerSize") } }

    init() {
        editorFont = d.string(forKey: "editorFont") ?? "IBM Plex Mono"
        editorSize = d.object(forKey: "editorSize") as? Double ?? 16
        lineWidth = d.object(forKey: "lineWidth") as? Int ?? 66
        widthCustom = d.bool(forKey: "widthCustom")
        headingSizes = d.object(forKey: "headingSizes") as? Bool ?? true
        showStatusBar = d.object(forKey: "showStatusBar") as? Bool ?? true
        viewerFont = d.string(forKey: "viewerFont") ?? "Source Serif 4"
        viewerSize = d.object(forKey: "viewerSize") as? Double ?? 18
    }

    /// The editor's body font: the chosen family, else SF Mono / the system monospaced font.
    func editorNSFont(size: CGFloat? = nil) -> NSFont {
        let s = size ?? CGFloat(editorSize)
        return Fonts.nsFont(family: editorFont, size: s) ?? .monospacedSystemFont(ofSize: s, weight: .regular)
    }

    var viewerBase: Font { Self.viewerFont(viewerFont, size: viewerSize) }

    static func viewerFont(_ name: String, size: CGFloat) -> Font {
        if Fonts.installed(name) { return .custom(name, size: size) }
        switch name {
        case "SF Pro", "Inter": return .system(size: size)
        default: return .system(size: size, design: .serif)    // New York
        }
    }
    func viewerFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Self.viewerFont(viewerFont, size: size).weight(weight)
    }
    var monoFont: (CGFloat) -> Font { { [self] s in
        Fonts.installed(editorFont) ? .custom(editorFont, size: s) : .system(size: s, design: .monospaced) } }
}
