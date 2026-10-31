import Foundation
import AppKit

/// The open file: its text, whether it has unsaved changes, and saving it back.
final class DocumentStore: ObservableObject {
    @Published private(set) var url: URL?
    @Published var text: String = "" {
        didSet { if !loading, text != oldValue { dirty = true; scheduleSave() } }
    }
    /// The file changed on disk while there were unsaved edits here.
    @Published var changedOnDisk = false
    @Published private(set) var error: String?

    private(set) var dirty = false
    private var loading = false
    private var modified: Date?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        for name in [NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.saveNow() })
        }
    }

    func open(_ url: URL?) {
        saveNow()
        self.url = url
        changedOnDisk = false
        load()
    }

    /// The file moved or was renamed; keep the text and the unsaved state.
    func relocate(to new: URL) { url = new; modified = Self.modDate(new) }

    private func load() {
        pending?.cancel()
        loading = true
        defer { loading = false; dirty = false }
        guard let url else { text = ""; modified = nil; return }
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            modified = Self.modDate(url)
            error = nil
        } catch {
            text = ""; modified = nil
            self.error = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    func saveNow() {
        pending?.cancel()
        guard dirty, let url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            modified = Self.modDate(url)
            dirty = false
            error = nil
        } catch {
            self.error = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// The folder was scanned again: pick up an outside change to the open file, or note that it is gone.
    func checkDisk() {
        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            if !dirty { open(nil) }
            return
        }
        guard let now = Self.modDate(url), now != modified else { return }
        if dirty { changedOnDisk = true } else { changedOnDisk = false; load() }
    }

    /// Keeps the edits here and writes over the outside change.
    func keepMine() { changedOnDisk = false; dirty = true; saveNow() }
    func reloadFromDisk() { changedOnDisk = false; load() }

    static func modDate(_ url: URL) -> Date? {
        // not URL.resourceValues: a URL caches what it was asked before
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: counts

    static func wordCount(_ text: String) -> Int {
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }
    static func readMinutes(words: Int) -> Int { max(1, Int((Double(words) / 200).rounded())) }
}
