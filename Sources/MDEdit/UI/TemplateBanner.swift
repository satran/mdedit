import SwiftUI

/// The bar above a template page while something is going on: a render in progress (with Cancel), or a read that is still blocked.
/// A page that is not being rendered has no bar: the editor shows the source and the preview button renders it.
struct TemplateBanner: View {
    @ObservedObject var ws: Workspace

    struct Content: Equatable {
        var text: String
        var spinner = false
        var buttons: [Button]
        struct Button: Equatable { var title: String; var enabled = true }
    }

    static let blocked = "Waiting for a blocked file read."

    /// What the bar says and offers; nil when there is nothing to say.
    static func content(_ state: TemplateState, busy: Bool) -> Content? {
        switch state {
        case .notTemplate, .rendered: return busy ? Content(text: blocked, buttons: []) : nil
        case .needsRender: return busy ? Content(text: blocked, buttons: []) : nil
        case .rendering: return Content(text: "Rendering…", spinner: true, buttons: [.init(title: "Cancel")])
        case .failed: return busy ? Content(text: blocked, buttons: []) : nil
        }
    }

    var body: some View {
        if let c = Self.content(ws.templateState, busy: ws.renderBusy) {
            InfoBar(text: c.text, spinner: c.spinner, actions: c.buttons.map { b in
                InfoBar.Action(title: b.title, enabled: b.enabled, run: { run(b.title) })
            })
        }
    }

    func run(_ title: String) { if title == "Cancel" { ws.cancelRender() } }
}
