import Foundation
import AppKit

/// The open file: its text, whether it has unsaved changes, and saving it back.
///
/// Rules that protect the file on disk:
/// - a file that cannot be read as text is never written back (`unreadable`);
/// - the file's own encoding, BOM and symlink are kept when saving;
/// - an outside change to the file is never written over without the user choosing (`changedOnDisk`);
/// - unsaved edits are written when the window closes, the app quits or another note opens — to a recovery copy
///   if the file itself is in conflict.
final class DocumentStore: ObservableObject {
    /// Larger files are not opened in the editor: every keystroke restyles the whole text.
    static let maxBytes = 10 * 1024 * 1024

    @Published private(set) var url: URL?
    @Published var text: String = "" {
        didSet { if !loading, !unreadable, text != oldValue { dirty = true; scheduleSave() } }
    }
    /// The file changed on disk while there were unsaved edits here.
    @Published var changedOnDisk = false
    @Published private(set) var error: String?
    /// The file could not be read as text (binary, too large, no permission). It is shown as an error and never saved.
    @Published private(set) var unreadable = false

    private(set) var dirty = false
    private var loading = false
    private var modified: Date?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var encoding: String.Encoding = .utf8
    private var hasBOM = false

    init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.saveNow() })
        observers.append(nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.flush() })
    }

    deinit {
        flush()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func open(_ url: URL?) {
        flush()
        self.url = url
        changedOnDisk = false
        load()
    }

    /// The file moved or was renamed; keep the text and the unsaved state.
    func relocate(to new: URL) { url = new; modified = Self.modDate(new) }

    // MARK: reading

    enum ReadError: LocalizedError {
        case tooLarge(Int), notText
        var errorDescription: String? {
            switch self {
            case .tooLarge(let n): return "it is \(n / 1_048_576) MB, too large to edit here"
            case .notText: return "it does not look like a text file"
            }
        }
    }

    /// Text from file bytes: UTF-8 first (with or without a BOM), then UTF-16 with a BOM, then Windows-1252 and Latin-1.
    static func decode(_ data: Data) throws -> (text: String, encoding: String.Encoding, bom: Bool) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) { return (s, .utf8, true) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) { return (s, .utf16, false) }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8, false) }
        // not UTF-8: only accept it as text if it has no NUL bytes, which text never has
        guard !data.contains(0) else { throw ReadError.notText }
        if let s = String(data: data, encoding: .windowsCP1252) { return (s, .windowsCP1252, false) }
        if let s = String(data: data, encoding: .isoLatin1) { return (s, .isoLatin1, false) }
        throw ReadError.notText
    }

    private func load() {
        pending?.cancel()
        loading = true
        defer { loading = false; dirty = false }
        unreadable = false
        encoding = .utf8; hasBOM = false
        guard let url else { text = ""; modified = nil; error = nil; return }
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)[.size] as? Int) ?? 0
            if size > Self.maxBytes { throw ReadError.tooLarge(size) }
            let decoded = try Self.decode(try Data(contentsOf: url))
            text = decoded.text; encoding = decoded.encoding; hasBOM = decoded.bom
            modified = Self.modDate(url)
            error = nil
        } catch {
            text = ""; modified = nil; unreadable = true
            self.error = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: writing

    private func scheduleSave() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    /// The bytes to write: the file's own encoding when it can hold the text, UTF-8 when it cannot.
    private func bytes() -> Data {
        if encoding != .utf8, let d = text.data(using: encoding) { return d }
        let utf8 = Data(text.utf8)
        return hasBOM && encoding == .utf8 ? Data([0xEF, 0xBB, 0xBF]) + utf8 : utf8
    }

    /// Writes unsaved edits. Does nothing while the file has changed on disk, unless `force`.
    func saveNow(force: Bool = false) {
        pending?.cancel()
        guard dirty, !unreadable, let url else { return }
        let target = url.resolvingSymlinksInPath()
        if !force, let m = modified, let now = Self.modDate(target), now != m {
            changedOnDisk = true
            return
        }
        do {
            try Self.replace(target, with: bytes())
            modified = Self.modDate(target)
            dirty = false
            error = nil
        } catch {
            self.error = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Writes a new file beside the old one and swaps them, so a crash never leaves half a note. The swap keeps what belongs to
    /// the file: permissions, creation date, Finder tags and other extended attributes (a plain atomic write drops them).
    static func replace(_ target: URL, with data: Data) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: target.path) else { try data.write(to: target, options: .atomic); return }
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? fm.removeItem(at: dir) }
        let temp = dir.appendingPathComponent(target.lastPathComponent)
        try data.write(to: temp)
        _ = try fm.replaceItemAt(target, withItemAt: temp, backupItemName: nil, options: [])
    }

    /// Everything unsaved goes to disk now; if the file itself is in conflict, to a copy beside it.
    func flush() {
        saveNow()
        guard dirty, !unreadable, let url else { return }
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + " (unsaved changes)"
        var copy = folder.appendingPathComponent(base)
        if !ext.isEmpty { copy.appendPathExtension(ext) }
        var n = 2
        while FileManager.default.fileExists(atPath: copy.path) {
            copy = folder.appendingPathComponent(base + " \(n)")
            if !ext.isEmpty { copy.appendPathExtension(ext) }
            n += 1
        }
        if (try? bytes().write(to: copy, options: .atomic)) != nil { dirty = false }
    }

    /// The folder was scanned again: pick up an outside change to the open file, or note that it is gone.
    func checkDisk() {
        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            if !dirty { open(nil) }
            return
        }
        guard let now = Self.modDate(url.resolvingSymlinksInPath()), now != modified else { return }
        if dirty { changedOnDisk = true } else { changedOnDisk = false; load() }
    }

    /// Keeps the edits here and writes over the outside change.
    func keepMine() { changedOnDisk = false; dirty = true; saveNow(force: true) }
    func reloadFromDisk() { changedOnDisk = false; load() }

    static func modDate(_ url: URL) -> Date? {
        // not URL.resourceValues: a URL caches what it was asked before
        (try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path))?[.modificationDate] as? Date
    }

    // MARK: counts

    static func wordCount(_ full: String) -> Int {
        let text = FrontMatter.body(of: full)
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }
    static func readMinutes(words: Int) -> Int { max(1, Int((Double(words) / 200).rounded())) }
}
