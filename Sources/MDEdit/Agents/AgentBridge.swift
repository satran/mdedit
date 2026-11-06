import Foundation

/// What the server hands a tool call to. The server knows HTTP and JSON-RPC only; the bridge knows the editor.
/// Tests give the server a stub.
struct AgentToolCall: @unchecked Sendable {
    let name: String
    let arguments: [String: Any]
    /// Who is asking, from the request's User-Agent (cut at 40 characters), or "Agent".
    let client: String
}

struct AgentToolResult: Sendable {
    /// The JSON text of the result, or of `{"code": ..., "message": ...}` when `isError`.
    let json: String
    let isError: Bool

    static func error(_ code: String, _ message: String) -> AgentToolResult {
        let body = try? JSONSerialization.data(withJSONObject: ["code": code, "message": message], options: [.sortedKeys])
        return AgentToolResult(json: String(decoding: body ?? Data(), as: UTF8.self), isError: true)
    }
}

@MainActor protocol AgentBridge: AnyObject {
    func call(_ call: AgentToolCall) -> AgentToolResult
    /// For tools that take time (a template render); the server uses this one.
    func callAsync(_ call: AgentToolCall) async -> AgentToolResult
}

extension AgentBridge {
    func callAsync(_ call: AgentToolCall) async -> AgentToolResult { self.call(call) }
}

/// Used until the editor tools exist, and whenever no window is open.
@MainActor final class NoWindowBridge: AgentBridge {
    func call(_ call: AgentToolCall) -> AgentToolResult { .error("no_window", "No MDEdit window is open.") }
}

/// The tools the server lists. Each has a JSON input schema.
enum AgentToolSpec {
    static let names = all.map { $0["name"] as! String }

    private static func tool(_ name: String, _ description: String, _ properties: [String: String], required: [String]) -> [String: Any] {
        let props = properties.mapValues { ["type": "string", "description": $0] as [String: Any] }
        return ["name": name, "description": description,
                "inputSchema": ["type": "object", "properties": props, "required": required, "additionalProperties": false] as [String: Any]]
    }

    static let all: [[String: Any]] = [
        tool("get_context", "What the person is looking at in the front MDEdit window: the open note, mode, unsaved flag, selection and the headings above the cursor.", [:], required: []),
        tool("read_note", "Read a note or text file (Markdown, text, HTML, JSON, YAML) in the open folder. Returns the unsaved text when it is open in the editor.", ["path": "Path relative to the folder"], required: ["path"]),
        tool("propose_edit", "Suggest a change to a note or text file (Markdown, text, HTML, JSON, YAML). Nothing changes until the person accepts it in the app. `old` must match the file's text exactly once.",
             ["path": "Path relative to the folder", "old": "Exact text to replace (must occur once)", "new": "Replacement text (may be empty)",
              "title": "Short title (up to 120 characters)", "reason": "Why (up to 500 characters)"], required: ["path", "old", "new", "title", "reason"]),
        tool("render_template", "Render an HTML template in the open folder with the same engine and limits as the Render button, and return the page or the error with its line number. Reads only; nothing is written and nothing opens. Use it to test a template before handing it over.",
             ["path": "Path of the .html or .htm template, relative to the folder", "query": "Optional query values the page sees as `query`, like due=overdue&priority=A",
              "today": "Optional date, yyyy-MM-dd, to render as if it were that day"], required: ["path"]),
        tool("get_proposal", "The state of a suggestion: pending, stale, accepted, rejected or withdrawn. Returns at once; poll.", ["id": "The id from propose_edit"], required: ["id"]),
    ]
}
