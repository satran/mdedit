import SwiftUI

/// Back and Forward from the side buttons of a mouse.
enum NavigationGesture {
    enum Step { case back, forward }

    /// Mice report their side buttons as "other" buttons 3 and 4. On this mouse 4 is the one under the thumb's back edge.
    static let backButton = 4, forwardButton = 3

    static func step(type: NSEvent.EventType, button: Int) -> Step? {
        guard type == .otherMouseDown else { return nil }
        return button == backButton ? .back : button == forwardButton ? .forward : nil
    }

    static func step(for event: NSEvent) -> Step? { step(type: event.type, button: event.buttonNumber) }
}

/// Watches the window it sits in for those buttons. A local monitor sees the event before the view under the pointer
/// (editor, web view, list) can use it.
struct NavigationGestures: NSViewRepresentable {
    let go: (NavigationGesture.Step) -> Void

    final class V: NSView {
        var go: (NavigationGesture.Step) -> Void = { _ in }
        private var monitor: Any?

        /// Passes the event on (nil when it was taken).
        func consume(_ event: NSEvent) -> NSEvent? {
            guard let step = NavigationGesture.step(for: event) else { return event }
            go(step)
            return nil
        }

        override func viewDidMoveToWindow() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
                guard let self, let w = self.window, event.window === w else { return event }
                return self.consume(event)
            }
        }

        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }

    func makeNSView(context: Context) -> V { let v = V(); v.go = go; return v }
    func updateNSView(_ v: V, context: Context) { v.go = go }
}
