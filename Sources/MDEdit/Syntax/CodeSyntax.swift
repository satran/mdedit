import Foundation

/// The kinds of file the editor shows as code (HTML, JSON, YAML) and the colours of their parts. Plain regular expressions, no parsing:
/// the editor only needs to tell tags from text and keys from values, and a file it cannot read well is still shown.
enum CodeKind: Equatable {
    case html, json, yaml

    init?(url: URL?) {
        guard let ext = url?.pathExtension.lowercased() else { return nil }
        if BinderNode.htmlExtensions.contains(ext) { self = .html }
        else if BinderNode.jsonExtensions.contains(ext) { self = .json }
        else if BinderNode.yamlExtensions.contains(ext) { self = .yaml }
        else { return nil }
    }
}

enum CodeRole { case comment, tag, string, key, number, keyword, template }

enum CodeSyntax {
    /// Beyond this size the file is shown without colours (styling runs on every edit).
    static let maxColoured = 300_000

    private static func rx(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: o) }

    private static let htmlRules: [(NSRegularExpression, CodeRole)] = [
        (rx("<[A-Za-z!/][^>]*>"), .tag),
        (rx("\"[^\"\\n]*\"|'[^'\\n]*'"), .string),
        (rx("\\{%.*?%\\}|\\{\\{.*?\\}\\}|\\{#.*?#\\}", .dotMatchesLineSeparators), .template),
        (rx("<!--.*?-->", .dotMatchesLineSeparators), .comment),
    ]
    private static let jsonRules: [(NSRegularExpression, CodeRole)] = [
        (rx("-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b"), .number),
        (rx("\\b(?:true|false|null)\\b"), .keyword),
        (rx("\"(?:[^\"\\\\\\n]|\\\\.)*\""), .string),
        (rx("\"(?:[^\"\\\\\\n]|\\\\.)*\"(?=\\s*:)"), .key),
    ]
    private static let yamlRules: [(NSRegularExpression, CodeRole)] = [
        (rx("-?\\b\\d+(?:\\.\\d+)?\\b"), .number),
        (rx("\\b(?:true|false|null|yes|no)\\b"), .keyword),
        (rx("\"(?:[^\"\\\\\\n]|\\\\.)*\"|'[^'\\n]*'"), .string),
        (rx("^[ \\t]*(?:- +)?(?:\"[^\"\\n]*\"|'[^'\\n]*'|[^\\s:#\\-\\[{][^:#\\n]*?)(?=:(?:\\s|$))", .anchorsMatchLines), .key),
        (rx("(?:^|(?<=\\s))#.*$", .anchorsMatchLines), .comment),
    ]

    /// Ranges to colour, later ones over earlier ones.
    static func spans(_ text: String, kind: CodeKind) -> [(range: NSRange, role: CodeRole)] {
        guard text.utf16.count <= maxColoured else { return [] }
        let rules: [(NSRegularExpression, CodeRole)]
        switch kind { case .html: rules = htmlRules; case .json: rules = jsonRules; case .yaml: rules = yamlRules }
        let all = NSRange(location: 0, length: (text as NSString).length)
        var out: [(NSRange, CodeRole)] = []
        for (re, role) in rules {
            re.enumerateMatches(in: text, range: all) { m, _, _ in
                if let r = m?.range, r.length > 0 { out.append((r, role)) }
            }
        }
        return out
    }
}
