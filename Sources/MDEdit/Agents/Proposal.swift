import Foundation
import Combine

enum ProposalStatus: String { case pending, stale, accepted, rejected, withdrawn }

/// A change an agent suggests. Nothing here touches a note: only `Workspace.accept` does, after a click.
struct Proposal: Identifiable {
    let id: String
    weak var workspace: Workspace?
    /// Relative to the window's folder.
    let path: String
    /// The note's real location, symlinks resolved.
    let url: URL
    let old: String
    let new: String
    let title: String
    let reason: String
    let client: String
    let createdAt: Date
    var status = ProposalStatus.pending
    var message = ""
    /// Where `old` is in the note's current text while the status is `pending`.
    var range: NSRange?
    var decidedAt: Date?

    var isOpen: Bool { status == .pending || status == .stale }
}

enum AcceptOutcome: Equatable { case applied, stale, blocked(String) }

/// The suggestions of all windows, in memory only. Owns the lifecycle: pending ⇄ stale, then accepted, rejected or withdrawn.
@MainActor final class ProposalStore: ObservableObject {
    static let shared = ProposalStore()

    static let maxOpenPerWindow = 20
    static let maxTitle = 120, maxReason = 500, maxText = 20_000

    @Published private(set) var items: [Proposal] = []
    /// How long a decided suggestion stays readable for the agent.
    var retention: TimeInterval = 600
    private let debounce: TimeInterval
    private var watchers: [ObjectIdentifier: AnyCancellable] = [:]

    init(debounce: TimeInterval = 0.25) { self.debounce = debounce }

    // MARK: reading

    func proposal(_ id: String) -> Proposal? { purge(); return items.first { $0.id == id } }
    func open(in ws: Workspace) -> [Proposal] { items.filter { $0.isOpen && $0.workspace === ws }.sorted { $0.createdAt > $1.createdAt } }

    /// What an agent is told.
    func report(_ id: String) -> (status: String, message: String)? {
        guard let p = proposal(id) else { return nil }
        if p.isOpen, p.workspace == nil { withdraw(id) }
        guard let p = proposal(id) else { return nil }
        return (p.status.rawValue, Self.message(for: p))
    }

    static func message(for p: Proposal) -> String {
        switch p.status {
        case .pending: return p.message.isEmpty ? "Waiting for the person to accept or reject it." : p.message
        case .stale: return "The text changed and the passage no longer matches exactly once."
        case .accepted: return "Accepted and applied."
        case .rejected: return "Rejected."
        case .withdrawn: return "Withdrawn: the window closed or agent access was switched off."
        }
    }

    // MARK: creating

    func propose(in ws: Workspace, path: String, old: String, new: String, title: String, reason: String, client: String) -> Result<Proposal, AgentTools.PathError> {
        typealias E = AgentTools.PathError
        purge()
        guard let root = ws.rootURL else { return .failure(E(code: "no_window", message: "The window has no folder open.")) }
        if BinderNode.htmlExtensions.contains((path as NSString).pathExtension.lowercased()) {
            return .failure(E(code: "not_editable", message: "HTML pages are shown read-only and cannot be edited."))
        }
        let url: URL
        switch AgentTools.resolve(path, in: root) {
        case .failure(let e): return .failure(e)
        case .success(let u): url = u
        }
        if old.isEmpty { return .failure(E(code: "no_match", message: "old must not be empty. To insert, include a neighbouring line in both old and new.")) }
        if old.utf16.count > Self.maxText || new.utf16.count > Self.maxText || title.count > Self.maxTitle || reason.count > Self.maxReason {
            return .failure(E(code: "too_large", message: "Limits: title \(Self.maxTitle) characters, reason \(Self.maxReason), old and new \(Self.maxText) UTF-16 units each."))
        }
        if items.filter({ $0.isOpen && $0.workspace === ws }).count >= Self.maxOpenPerWindow {
            return .failure(E(code: "too_many_pending", message: "There are already \(Self.maxOpenPerWindow) suggestions waiting. The person has to decide some first."))
        }
        guard let text = Self.text(of: url, in: ws) else { return .failure(E(code: "not_a_note", message: "That file cannot be read as text.")) }
        let found = Self.matches(of: old, in: text)
        if found.count != 1 {
            return .failure(E(code: found.isEmpty ? "no_match" : "ambiguous_match",
                              message: found.isEmpty ? "old was not found in the note. It must match exactly, character for character."
                                                     : "old matches \(found.count) places. Include more surrounding text so it matches once."))
        }
        let p = Proposal(id: UUID().uuidString.lowercased().prefix(12).description, workspace: ws, path: path, url: url, old: old, new: new, title: title,
                         reason: reason, client: client, createdAt: Date(), range: found[0])
        items.append(p)
        watch(ws)
        return .success(p)
    }

    /// The note's current text: the editor's when it is open, else the file.
    static func text(of url: URL, in ws: Workspace) -> String? {
        if let open = ws.document.url, open.resolvingSymlinksInPath() == url { return ws.document.text }
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.count <= DocumentStore.maxBytes else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Where `needle` occurs, overlaps included, byte-exact. Stops counting at 1,000.
    nonisolated static func matches(of needle: String, in text: String) -> [NSRange] {
        let ns = text as NSString, n = needle as NSString
        guard n.length > 0, ns.length >= n.length else { return [] }
        var out: [NSRange] = []
        var from = 0
        while from <= ns.length - n.length, out.count < 1_000 {
            let r = ns.range(of: needle, options: .literal, range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            out.append(r); from = r.location + 1
        }
        return out
    }

    // MARK: the stale check

    /// Re-searches `old` for the suggestions of the note that is open. Cost: at most 20 searches per call.
    func recheck(_ ws: Workspace) {
        guard let open = ws.document.url?.resolvingSymlinksInPath() else { return }
        let text = ws.document.text
        for i in items.indices where items[i].isOpen && items[i].workspace === ws && items[i].url == open {
            let found = Self.matches(of: items[i].old, in: text)
            if found.count == 1 { items[i].status = .pending; items[i].range = found[0] }
            else { items[i].status = .stale; items[i].range = nil }
        }
    }

    private func watch(_ ws: Workspace) {
        let key = ObjectIdentifier(ws)
        guard watchers[key] == nil else { return }
        // 250 ms after the last change of the text or the note, not on every keystroke
        watchers[key] = ws.document.$text.map { _ in () }.merge(with: ws.document.$url.map { _ in () })
            .debounce(for: .seconds(debounce), scheduler: RunLoop.main)
            .sink { [weak self, weak ws] in
                guard let self, let ws else { return }
                self.recheck(ws)
                if !self.items.contains(where: { $0.isOpen && $0.workspace === ws }) { self.watchers[ObjectIdentifier(ws)] = nil }
            }
    }

    // MARK: deciding

    func reject(_ id: String) { decide(id, .rejected) }
    func withdraw(_ id: String) { decide(id, .withdrawn) }
    func withdrawAll() { for p in items where p.isOpen { decide(p.id, .withdrawn) } }

    private func decide(_ id: String, _ status: ProposalStatus) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].isOpen else { return }
        items[i].status = status; items[i].range = nil; items[i].decidedAt = Date()
    }

    /// Applies one suggestion through the editor (see `Workspace.accept`) and records the result.
    @discardableResult
    func accept(_ id: String) async -> AcceptOutcome {
        guard let p = proposal(id), p.isOpen else { return .blocked("That suggestion is already decided.") }
        guard let ws = p.workspace else { withdraw(id); return .blocked("The window is closed.") }
        guard p.status == .pending else { return .stale }
        let outcome = await ws.accept(p)
        switch outcome {
        case .applied: decide(id, .accepted)
        case .stale: if let i = items.firstIndex(where: { $0.id == id }) { items[i].status = .stale; items[i].range = nil }
        case .blocked(let why): if let i = items.firstIndex(where: { $0.id == id }) { items[i].message = why }
        }
        recheck(ws)   // an overlapping suggestion is now stale
        return outcome
    }

    private func purge() {
        let cutoff = Date().addingTimeInterval(-retention)
        items.removeAll { !$0.isOpen && ($0.decidedAt ?? .distantPast) < cutoff }
    }
}
