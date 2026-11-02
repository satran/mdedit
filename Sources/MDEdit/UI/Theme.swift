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
    static let strongText = dyn(0x15171A, 0xF3F4F6)
    static let quoteText = dyn(0x4A4F56, 0xA9AEB6)
    static let marker = dyn(0xAEB4BC, 0x5D626B)
    static let link = dyn(0x2F6FDB, 0x6FA3F7)
    static let caret = dyn(0x3478F6, 0x4C8DF6)
    static let chip = dyn(0xF2F4F7, 0x2C2E33)
    static let rule = dyn(0xD7DCE2, 0x42454C)
    static let segmentTrack = dyn(0xEEF0F3, 0x2B2D31)
    static let segmentOn = dyn(0xFFFFFF, 0x42454C)
    static let segmentText = dyn(0x5F656D, 0xB3B8BF)
    static let highlight = dyn(0xFFE58A, 0x6B5A1E)
    static let findMatch = dyn(0xFCEFB4, 0x4D4322)           // a find match in the note
    static let findCurrent = dyn(0xFAD551, 0x7A6624)         // the one the panel is on
    static let removedBg = dyn(0xFBE2DF, 0x4A2A2A), removedInk = dyn(0x9B2C2C, 0xF0A0A0)
    static let addedBg = dyn(0xDCF2E3, 0x1F3D2B), addedInk = dyn(0x1E6B3A, 0x8EDBA8)
    static let done = dyn(0x8A9099, 0x7B8089)
    static let unresolved = dyn(0x9AA0A8, 0x7C828B)
    static let focusDim = dyn(0xC3C8CE, 0x4A4E55)
    static let green = dyn(0x2E8B57, 0x58C98A)

    // type specs: editor
    static let linkText = dyn(0x2453B3, 0x7FA8F5)            // the words of a link
    static let selectionText = dyn(0xCFE0FB, 0x2F4A73)       // selected text
    static let fmKey = dyn(0x9AA0A8, 0x7C828B)               // front matter: key, value, fence
    static let fmValue = dyn(0x7C828A, 0x9BA1A9)
    static let fmFence = dyn(0xB4BAC2, 0x5D626B)
    static let codeBand = dyn(0xF6F7F9, 0x292B2F)            // a code block
    static let codeInk = dyn(0x2F3338, 0xD3D7DC)
    static let inlineCode = dyn(0xF2F4F7, 0x2E3035)

    // type specs: viewer
    static let vInkSerif = dyn(0x24272B, 0xDCDFE3), vInkSans = dyn(0x25282C, 0xDCDFE3)
    static let vHeadSerif = dyn(0x15171A, 0xF3F4F6), vHeadSans = dyn(0x131518, 0xF3F4F6)
    static let vQuoteSerif = dyn(0x3B4045, 0xA9AEB6), vQuoteSans = dyn(0x4A4F56, 0xA9AEB6)
    static let vQuoteBar = dyn(0xD9DEE4, 0x42454C)
    static let vBulletSerif = dyn(0x8C929A, 0x7B8089), vBulletSans = dyn(0x9AA0A8, 0x7B8089)
    static let vRule = dyn(0xD5D9DF, 0x42454C)
    static let vRowLine = dyn(0xECEEF1, 0x2F3136)
    static let vLabel = dyn(0x6A7078, 0x9BA1A9)
    static let vSecondary = dyn(0x4A4F56, 0xA9AEB6)
    static let vChip = dyn(0xF1F3F5, 0x2E3035)
    static let vCard = dyn(0xE4E7EB, 0x34363B)
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

/// Centres the traffic lights in the header row, level with the header's buttons.
struct TrafficLights: NSViewRepresentable {
    final class V: NSView {
        private var observers: [NSObjectProtocol] = []
        private var step: CGFloat?
        override func viewDidMoveToWindow() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let w = window else { return }
            // a change of appearance makes AppKit lay the title bar out again, so look again after every update
            for n in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didUpdateNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { [weak self] _ in self?.place() })
            }
            DispatchQueue.main.async { self.place() }
        }
        func place() {
            guard let w = window, !w.styleMask.contains(.fullScreen),
                  let close = w.standardWindowButton(.closeButton), let bar = close.superview, let container = bar.superview else { return }
            let h = Metrics.headerHeight
            let barFrame = NSRect(x: container.frame.minX, y: w.frame.height - h, width: container.frame.width, height: h)
            if container.frame != barFrame { container.frame = barFrame }
            if bar.frame != container.bounds { bar.frame = container.bounds }
            // keep the system spacing, but start further in from the left edge
            if step == nil, let mini = w.standardWindowButton(.miniaturizeButton), mini.frame.minX > close.frame.minX { step = mini.frame.minX - close.frame.minX }
            for (i, t) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let b = w.standardWindowButton(t), b.superview === bar else { continue }
                let origin = NSPoint(x: 20 + CGFloat(i) * (step ?? 20), y: (bar.bounds.height - b.frame.height) / 2)
                if b.frame.origin != origin { b.setFrameOrigin(origin) }
            }
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) {}
}
