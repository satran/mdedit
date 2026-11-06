import Foundation

/// File name patterns for `match`: `*` is any run of characters, `?` is one character; the rest must be equal, ignoring case.
/// No regular expressions, so a pattern cannot be made to run for long: the work is at most the pattern length times the name length.
enum TemplateGlob {
    static func matches(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern.lowercased()), n = Array(name.lowercased())
        var pi = 0, ni = 0
        var star = -1, mark = 0
        while ni < n.count {
            if pi < p.count, p[pi] == "?" || p[pi] == n[ni], p[pi] != "*" { pi += 1; ni += 1 }
            else if pi < p.count, p[pi] == "*" { star = pi; mark = ni; pi += 1 }
            else if star >= 0 { pi = star + 1; mark += 1; ni = mark }
            else { return false }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
