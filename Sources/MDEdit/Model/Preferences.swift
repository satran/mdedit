import SwiftUI
import Security

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
    /// Characters per line in the viewer; 68 gives the type specs' own column (36 em).
    @Published var viewerWidth: Int { didSet { d.set(viewerWidth, forKey: "viewerWidth") } }
    @Published var viewerWidthCustom: Bool { didSet { d.set(viewerWidthCustom, forKey: "viewerWidthCustom") } }
    /// The viewer's font family (Inter by default). The custom stylesheet can still override it.
    @Published var viewerFont: String { didSet { d.set(viewerFont, forKey: "viewerFont") } }
    /// The viewer's body size in points (18 by default, as in the type specs).
    @Published var viewerSize: Double { didSet { d.set(viewerSize, forKey: "viewerTextSize") } }

    /// Look for a new release at launch (once a day). The only request the app makes on its own.
    @Published var checkForUpdates: Bool { didSet { d.set(checkForUpdates, forKey: "checkForUpdates") } }

    /// Agent access: a local server that lets an agent read the editor's context and propose edits. Off until turned on here.
    @Published var agentsEnabled: Bool { didSet { d.set(agentsEnabled, forKey: "agentsEnabled") } }
    /// The loopback port the server listens on.
    @Published var agentPort: Int { didSet { d.set(agentPort, forKey: "agentPort") } }
    /// The bearer token an agent must send. Made on first use; a new one signs every agent out.
    @Published private(set) var agentToken: String { didSet { d.set(agentToken, forKey: "agentToken") } }

    /// What Settings and the size and margin shortcuts stay within.
    static let editorSizeRange = 11.0...28.0
    static let viewerSizeRange = 12.0...28.0
    static let editorWidthRange = 40...160
    static let viewerWidthRange = 40...120
    static let marginStep = 4

    /// ⌘= and ⌘-: a point bigger or smaller, for the viewer when `viewer`, else for the editor.
    func changeTextSize(by step: Double, viewer: Bool) {
        if viewer { viewerSize = min(Self.viewerSizeRange.upperBound, max(Self.viewerSizeRange.lowerBound, viewerSize + step)) }
        else { editorSize = min(Self.editorSizeRange.upperBound, max(Self.editorSizeRange.lowerBound, editorSize + step)) }
    }

    /// ⇧⌘= and ⇧⌘-: wider margins (`direction` 1) are a narrower line, and the other way round.
    func changeMargins(direction: Int, viewer: Bool) {
        let delta = -direction * Self.marginStep
        if viewer {
            viewerWidth = min(Self.viewerWidthRange.upperBound, max(Self.viewerWidthRange.lowerBound, viewerWidth + delta))
            viewerWidthCustom = !SettingsView.viewerPresets.contains { $0.1 == viewerWidth }
        } else {
            lineWidth = min(Self.editorWidthRange.upperBound, max(Self.editorWidthRange.lowerBound, lineWidth + delta))
            widthCustom = !SettingsView.presets.contains { $0.1 == lineWidth }
        }
    }

    static let agentPortRange = 1024...65_535
    static let defaultAgentPort = 47_821

    /// 32 random bytes from the system, as 64 hex characters.
    static func makeAgentToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            // never fall back to something guessable: two UUIDs are 244 random bits from the same source
            return (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func regenerateAgentToken() { agentToken = Self.makeAgentToken() }

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
        viewerFont = Self.cleanFamily(d.string(forKey: "viewerFont")) ?? ViewerStyle.defaultFamily
        viewerSize = min(32, max(12, d.object(forKey: "viewerTextSize") as? Double ?? Double(ViewerStyle.specBody)))
        checkForUpdates = d.object(forKey: "checkForUpdates") as? Bool ?? true
        agentsEnabled = d.bool(forKey: "agentsEnabled")
        agentPort = min(Self.agentPortRange.upperBound, max(Self.agentPortRange.lowerBound, d.object(forKey: "agentPort") as? Int ?? Self.defaultAgentPort))
        // a stored token that is not what we make (short, odd characters) is replaced, never trusted
        let saved = d.string(forKey: "agentToken") ?? ""
        let valid = saved.count == 64 && saved.allSatisfy { $0.isHexDigit && !$0.isUppercase }
        agentToken = valid ? saved : Self.makeAgentToken()
        if !valid { d.set(agentToken, forKey: "agentToken") }
        Self.forgetShellSettings(in: d)
    }

    /// Shell commands were removed (plan 007). Their saved settings are deleted once, from the app's own settings only;
    /// nothing in any folder is touched.
    static func forgetShellSettings(in d: UserDefaults) {
        guard !d.bool(forKey: "removedShellSettings") else { return }
        for key in ["shellEnabled", "shellPath", "shellSearchPath", "shellEnvironment", "shellTimeout", "shellHistory", "shellDestination"] { d.removeObject(forKey: key) }
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("shellApproved:") { d.removeObject(forKey: key) }
        d.set(true, forKey: "removedShellSettings")
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

    /// A font family name that is safe to put in a stylesheet: letters, digits, spaces and hyphens, 60 characters at most.
    static func cleanFamily(_ name: String?) -> String? {
        let f = String((name ?? "").filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }.prefix(60)).trimmingCharacters(in: .whitespaces)
        return f.isEmpty ? nil : f
    }

    /// Every size, spacing and colour of the viewer, with the chosen font (the type specs).
    var viewerStyle: ViewerStyle { ViewerStyle(body: CGFloat(viewerSize), family: viewerFont, width: viewerWidth) }

    var monoFont: (CGFloat) -> Font { { [self] s in
        Fonts.installed(editorFont) ? .custom(editorFont, size: s) : .system(size: s, design: .monospaced) } }
}
