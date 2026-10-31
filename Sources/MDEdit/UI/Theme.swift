import SwiftUI
import AppKit

/// Flat, solid colours (no materials), light and dark. Values come from plan/design.html.
enum Palette {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    // binder
    static let binderBg = dyn(0xF4F5F7, 0x25262A)
    static let binderBorder = dyn(0xE2E5E9, 0x34363B)
    static let binderText = dyn(0x2B2E33, 0xDFE1E5)
    static let muted = dyn(0x686E76, 0x9BA1A9)
    static let field = dyn(0xE7E9ED, 0x303237)
    static let selection = dyn(0xDFE5EE, 0x3A404A)

    // writing pane
    static let paneBg = dyn(0xFFFFFF, 0x1E1F22)
    static let paneBorder = dyn(0xEFF1F3, 0x2C2E33)
    static let text = dyn(0x2A2D31, 0xDCDFE3)
    static let strongText = dyn(0x1E2024, 0xF3F4F6)
    static let quoteText = dyn(0x4A4F56, 0xA9AEB6)
    static let marker = dyn(0xB4BAC2, 0x5D626B)
    static let link = dyn(0x2F6FDB, 0x6FA3F7)
    static let caret = dyn(0x3478F6, 0x4C8DF6)
    static let chip = dyn(0xF2F4F7, 0x2C2E33)
    static let rule = dyn(0xD7DCE2, 0x42454C)
    static let segmentTrack = dyn(0xEEF0F3, 0x2B2D31)
    static let segmentOn = dyn(0xFFFFFF, 0x42454C)
    static let segmentText = dyn(0x5F656D, 0xB3B8BF)
    static let highlight = dyn(0xFFE58A, 0x6B5A1E)
    static let done = dyn(0x8A9099, 0x7B8089)
    static let unresolved = dyn(0x9AA0A8, 0x7C828B)
    static let focusDim = dyn(0xC3C8CE, 0x4A4E55)
    static let green = dyn(0x2E8B57, 0x58C98A)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(_ ns: NSColor) { self.init(nsColor: ns) }
}

enum Metrics {
    static let headerHeight: CGFloat = 52
    static let footerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 24
    static let indent: CGFloat = 16
    static let column: CGFloat = 640
}

/// Lets the window be dragged from this area (the title bar is hidden).
struct WindowDragArea: NSViewRepresentable {
    final class V: NSView { override var mouseDownCanMoveWindow: Bool { true } }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) {}
}
