import Foundation

/// A JSON or YAML file read as a value, for `{% data path as d %}`.
///
/// JSON is read in full. YAML is the same small subset as the properties block of a note (`key: value` lines, `[a, b]` and `- a`
/// lists, `true`/`false`; no nesting): use JSON for nested data. A JSON `true` is the text "true", a `false` and a `null` are empty,
/// an integer is a number, anything else (a fraction, a very large number) is the text as written.
enum TemplateData {
    enum Failure: Error { case notText, tooLarge }

    static func parse(_ data: Data, isYAML: Bool, limits: TemplateLimits) throws -> Value {
        if isYAML {
            guard let text = String(data: data, encoding: .utf8) else { throw Failure.notText }
            let wrapped = text.hasPrefix("---") ? text : "---\n" + text + "\n---\n"
            return TemplateSources.metaRecord(wrapped)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { throw Failure.notText }
        var count = 0
        return try map(object, depth: 0, count: &count, limits: limits)
    }

    private static func map(_ o: Any, depth: Int, count: inout Int, limits: TemplateLimits) throws -> Value {
        count += 1
        if count > limits.dataValues || depth > limits.dataDepth { throw Failure.tooLarge }
        switch o {
        case let s as String: return .text(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? .text("true") : .empty }
            if CFNumberIsFloatType(n) == false, abs(n.int64Value) < 1_000_000_000 { return .number(Int(n.int64Value)) }
            return .text(n.stringValue)
        case let a as [Any]: return .list(try a.map { try map($0, depth: depth + 1, count: &count, limits: limits) })
        case let d as [String: Any]:
            var r: [String: Value] = [:]
            for (k, v) in d { r[k] = try map(v, depth: depth + 1, count: &count, limits: limits) }
            return .record(r)
        default: return .empty
        }
    }
}
