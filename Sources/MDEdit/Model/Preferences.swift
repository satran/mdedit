import SwiftUI

/// What Settings changes. Fonts fall back when a family is not installed.
final class Preferences: ObservableObject {
    static let shared = Preferences(defaults: AppEnvironment.defaults)
    private let d: UserDefaults

    @Published var editorFont: String { didSet { d.set(editorFont, forKey: "editorFont") } }
    @Published var editorSize: Double { didSet { d.set(editorSize, forKey: "editorSize") } }
    /// Characters per line in the editor.
    @Published var lineWidth: Int { didSet { d.set(lineWidth, forKey: "lineWidth") } }
    /// The "Custom" width is picked, even if its number happens to match a preset.
    @Published var widthCustom: Bool { didSet { d.set(widthCustom, forKey: "widthCustom") } }
    /// Headings in the editor are larger than body text; off keeps them the body size (still bold).
    @Published var headingSizes: Bool { didSet { d.set(headingSizes, forKey: "headingSizes") } }
    @Published var showStatusBar: Bool { didSet { d.set(showStatusBar, forKey: "showStatusBar") } }
    /// "auto" follows the system; "light" and "dark" override it for the whole app.
    @Published var theme: String { didSet { d.set(theme, forKey: "theme"); applyTheme() } }
    /// Distraction free mode takes the window full screen; off keeps it in its window.
    @Published var focusFullScreen: Bool { didSet { d.set(focusFullScreen, forKey: "focusFullScreen") } }
    /// Pictures from the web load only when this is on: a remote picture tells its server that the note was opened.
    @Published var loadRemoteImages: Bool { didSet { d.set(loadRemoteImages, forKey: "loadRemoteImages") } }
    /// Characters per line in the viewer; 68 gives the type specs' own column (34 em serif, 36 em sans).
    @Published var viewerWidth: Int { didSet { d.set(viewerWidth, forKey: "viewerWidth") } }
    @Published var viewerWidthCustom: Bool { didSet { d.set(viewerWidthCustom, forKey: "viewerWidthCustom") } }
    /// "serif" (Literata) or "sans" (Inter): the two reading templates of the viewer.
    @Published var viewerTemplate: String { didSet { d.set(viewerTemplate, forKey: "viewerTemplate") } }
    /// The serif template's body size in points (20 by default); the sans template runs 2 points smaller, as in the type specs.
    @Published var viewerSize: Double { didSet { d.set(viewerSize, forKey: "viewerSize") } }

    /// Shell commands from the editor (⌘R). Off until turned on here.
    @Published var shellEnabled: Bool { didSet { d.set(shellEnabled, forKey: "shellEnabled") } }
    /// The program that runs a command: `shell -c "command"`.
    @Published var shellPath: String { didSet { d.set(shellPath, forKey: "shellPath") } }
    /// The PATH commands get. Nothing else of the app's own environment is passed on.
    @Published var shellSearchPath: String { didSet { d.set(shellSearchPath, forKey: "shellSearchPath") } }
    /// Extra variables for commands, one `KEY=value` per line.
    @Published var shellEnvironment: String { didSet { d.set(shellEnvironment, forKey: "shellEnvironment") } }
    /// Seconds before a command is stopped.
    @Published var shellTimeout: Int { didSet { d.set(shellTimeout, forKey: "shellTimeout") } }
    /// Commands kept in `.mdedit/history` in the folder; 0 keeps none.
    @Published var shellHistory: Int { didSet { d.set(shellHistory, forKey: "shellHistory") } }

    init(defaults: UserDefaults = AppEnvironment.defaults) {
        d = defaults
        editorFont = d.string(forKey: "editorFont") ?? "IBM Plex Mono"
        editorSize = min(72, max(8, d.object(forKey: "editorSize") as? Double ?? 17))
        lineWidth = min(200, max(20, d.object(forKey: "lineWidth") as? Int ?? 72))
        widthCustom = d.bool(forKey: "widthCustom")
        headingSizes = d.object(forKey: "headingSizes") as? Bool ?? false
        showStatusBar = d.object(forKey: "showStatusBar") as? Bool ?? true
        theme = ["auto", "light", "dark"].contains(d.string(forKey: "theme") ?? "") ? d.string(forKey: "theme")! : "auto"
        focusFullScreen = d.object(forKey: "focusFullScreen") as? Bool ?? true
        loadRemoteImages = d.bool(forKey: "loadRemoteImages")
        viewerWidth = min(140, max(30, d.object(forKey: "viewerWidth") as? Int ?? 68))
        viewerWidthCustom = d.bool(forKey: "viewerWidthCustom")
        viewerTemplate = d.string(forKey: "viewerTemplate") == "sans" ? "sans" : "serif"
        viewerSize = min(32, max(14, d.object(forKey: "viewerSize") as? Double ?? 20))
        shellEnabled = d.bool(forKey: "shellEnabled")
        shellPath = String((d.string(forKey: "shellPath") ?? ShellEnvironment.defaultShell).prefix(1024))
        shellSearchPath = String((d.string(forKey: "shellSearchPath") ?? ShellEnvironment.defaultPath).prefix(4096))
        shellEnvironment = String((d.string(forKey: "shellEnvironment") ?? "").prefix(16 * 1024))
        shellTimeout = min(600, max(1, d.object(forKey: "shellTimeout") as? Int ?? 30))
        shellHistory = min(500, max(0, d.object(forKey: "shellHistory") as? Int ?? 50))
    }

    func applyTheme() {
        NSApplication.shared.appearance = switch theme {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    /// The editor's body font: the chosen family, else SF Mono / the system monospaced font.
    func editorNSFont(size: CGFloat? = nil) -> NSFont {
        let s = size ?? CGFloat(editorSize)
        return Fonts.nsFont(family: editorFont, size: s) ?? .monospacedSystemFont(ofSize: s, weight: .regular)
    }

    /// The family of the chosen template; the exported HTML names it too.
    var viewerFont: String { viewerTemplate == "sans" ? "Inter" : "Literata" }

    /// Every size, spacing and colour of the viewer for the chosen template (the type specs).
    var viewerStyle: ViewerStyle { ViewerStyle(template: viewerTemplate == "sans" ? .sans : .serif, serifBody: CGFloat(viewerSize), width: viewerWidth) }

    var monoFont: (CGFloat) -> Font { { [self] s in
        Fonts.installed(editorFont) ? .custom(editorFont, size: s) : .system(size: s, design: .monospaced) } }
}
