import AppKit
import Quartz

/// The Quick Look panel, for files the editor cannot show: a click in the binder brings up a preview.
final class QuickView: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickView()
    private var url: URL?

    func show(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
    }

    /// Opening a note puts the panel away.
    func hide() {
        url = nil
        if QLPreviewPanel.sharedPreviewPanelExists(), let p = QLPreviewPanel.shared(), p.isVisible { p.orderOut(nil) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL? }
}
