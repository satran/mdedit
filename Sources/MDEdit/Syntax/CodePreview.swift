import Foundation

/// The preview of a JSON or YAML file, made as Markdown so it is drawn by the same page as a note: a YAML file becomes a table of its
/// keys and values, a JSON file becomes its text laid out with indentation. Everything the file says is data: it goes through the
/// Markdown renderer, which escapes it.
enum CodePreview {
    /// Largest file shown; beyond it the preview says so (the editor still shows the file).
    static let maxBytes = 1_000_000
    static let maxRows = 2_000

    static func markdown(json text: String) -> String {
        guard text.utf8.count <= maxBytes else { return "This file is larger than \(maxBytes / 1_000) KB. The preview shows files up to that size.\n" }
        guard let data = text.data(using: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "This file is empty.\n" }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
            return fenced(String(decoding: pretty, as: UTF8.self), language: "json")
        } catch {
            let why = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
            return "**This is not valid JSON.** \(escape(why))\n\n" + fenced(text, language: "")
        }
    }

    static func markdown(yaml text: String) -> String {
        guard text.utf8.count <= maxBytes else { return "This file is larger than \(maxBytes / 1_000) KB. The preview shows files up to that size.\n" }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "This file is empty.\n" }
        guard let node = YAMLReader.parse(text) else {
            return "**This YAML could not be read as a table.** The preview shows the small subset of YAML it understands: mappings, lists and plain values.\n\n" + fenced(text, language: "yaml")
        }
        var rows: [(String, String)] = []
        flatten(node, prefix: "", into: &rows)
        if rows.isEmpty { return "This file has no values.\n" }
        var out = "| Key | Value |\n|---|---|\n"
        for (k, v) in rows.prefix(maxRows) { out += "| \(cell(k)) | \(cell(v)) |\n" }
        if rows.count > maxRows { out += "\n\(rows.count - maxRows) more rows are not shown.\n" }
        return out
    }

    /// Nested keys are joined with dots; a list of plain values is one row; a list of maps has a row per field (`items[1].name`).
    static func flatten(_ node: YAMLNode, prefix: String, into rows: inout [(String, String)]) {
        guard rows.count <= maxRows else { return }
        switch node {
        case .scalar(let s): rows.append((prefix.isEmpty ? "(value)" : prefix, s))
        case .map(let entries):
            for e in entries { flatten(e.value, prefix: prefix.isEmpty ? e.key : prefix + "." + e.key, into: &rows) }
        case .list(let items):
            if items.allSatisfy({ if case .scalar = $0 { return true }; return false }) {
                rows.append((prefix.isEmpty ? "(list)" : prefix, items.map { if case .scalar(let s) = $0 { return s }; return "" }.joined(separator: ", ")))
            } else {
                for (i, item) in items.enumerated() { flatten(item, prefix: "\(prefix)[\(i + 1)]", into: &rows) }
            }
        }
    }

    // MARK: Markdown helpers

    /// A cell holds one line: pipes and backslashes are escaped, line breaks become a visible mark.
    static func cell(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ⏎ ")
        return escape(oneLine)
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for c in s {
            if "\\|`*_[]<>&#".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    /// A code block whose fence is longer than any run of backticks in the text, so the text cannot close it.
    static func fenced(_ text: String, language: String) -> String {
        var longest = 0, run = 0
        for c in text { if c == "`" { run += 1; longest = max(longest, run) } else { run = 0 } }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return fence + language + "\n" + text + "\n" + fence + "\n"
    }
}
