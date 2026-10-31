import SwiftUI

/// What Settings changes. Fonts fall back when a family is not installed.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    @Published var editorFont: String { didSet { d.set(editorFont, forKey: "editorFont") } }
    @Published var editorSize: Double { didSet { d.set(editorSize, forKey: "editorSize") } }
    /// Characters per line in the editor.
    @Published var lineWidth: Int { didSet { d.set(lineWidth, forKey: "lineWidth") } }
    @Published var viewerFont: String { didSet { d.set(viewerFont, forKey: "viewerFont") } }
    @Published var viewerSize: Double { didSet { d.set(viewerSize, forKey: "viewerSize") } }

    init() {
        editorFont = d.string(forKey: "editorFont") ?? "IBM Plex Mono"
        editorSize = d.object(forKey: "editorSize") as? Double ?? 16
        lineWidth = d.object(forKey: "lineWidth") as? Int ?? 66
        viewerFont = d.string(forKey: "viewerFont") ?? "Source Serif 4"
        viewerSize = d.object(forKey: "viewerSize") as? Double ?? 18
    }

    /// The editor's body font: the chosen family, else SF Mono / the system monospaced font.
    func editorNSFont(size: CGFloat? = nil) -> NSFont {
        let s = size ?? CGFloat(editorSize)
        return NSFont(name: editorFont, size: s) ?? NSFont(name: "SFMono-Regular", size: s) ?? .monospacedSystemFont(ofSize: s, weight: .regular)
    }

    var viewerBase: Font { Self.viewerFont(viewerFont, size: viewerSize) }

    static func viewerFont(_ name: String, size: CGFloat) -> Font {
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        switch name {
        case "SF Pro", "Inter": return .system(size: size)
        default: return .system(size: size, design: .serif)    // New York
        }
    }
    func viewerFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Self.viewerFont(viewerFont, size: size).weight(weight)
    }
    var monoFont: (CGFloat) -> Font { { [self] s in
        NSFont(name: editorFont, size: s) != nil ? .custom(editorFont, size: s) : .system(size: s, design: .monospaced) } }
}
