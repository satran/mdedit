import SwiftUI

/// The bar above an HTML page that uses template tags: Render, a render in progress, and the outcome.
struct TemplateBanner: View {
    @ObservedObject var ws: Workspace

    struct Content: Equatable {
        var text: String
        var spinner = false
        var buttons: [Button]
        struct Button: Equatable { var title: String; var enabled = true }
    }

    static let blocked = "Waiting for a blocked file read."

    /// What the bar says and offers for a state; nil when the page has no template tags.
    static func content(_ state: TemplateState, busy: Bool) -> Content? {
        switch state {
        case .notTemplate: return nil
        case .needsRender:
            return Content(text: busy ? blocked : "This page uses template tags.", buttons: [.init(title: "Render", enabled: !busy)])
        case .rendering:
            return Content(text: "Rendering…", spinner: true, buttons: [.init(title: "Cancel")])
        case .cancelled:
            return Content(text: busy ? "Render cancelled. " + blocked : "Render cancelled.", buttons: [.init(title: "Render", enabled: !busy)])
        case .rendered:
            return Content(text: "Rendered from template.", buttons: [.init(title: "Show source")])
        case .failed(let e):
            return Content(text: e.message + (e.line.map { " (line \($0))" } ?? "") + (busy ? " " + blocked : ""), buttons: [.init(title: "Show source")])
        }
    }

    var body: some View {
        if let c = Self.content(ws.templateState, busy: ws.renderBusy) {
            InfoBar(text: c.text, spinner: c.spinner, actions: c.buttons.map { b in
                InfoBar.Action(title: b.title, enabled: b.enabled, run: { run(b.title) })
            })
        }
    }

    func run(_ title: String) {
        switch title {
        case "Render": ws.render()
        case "Cancel": ws.cancelRender()
        default: ws.showTemplateSource()
        }
    }
}
