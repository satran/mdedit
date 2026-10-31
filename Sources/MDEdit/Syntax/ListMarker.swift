import Foundation

/// What a new line after a Markdown list item should start with: "- a" gives "- ", "3. a" gives "4. ", "- [x] a" gives "- [ ] ".
struct ListMarker: Equatable {
    var prefix: String   // the marker as typed, indentation included
    var next: String

    init?(line: String) {
        let spaces = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(spaces.count)
        if let f = rest.first, "-*+•".contains(f), rest.dropFirst().first == " " {
            var p = "\(f) "
            var n = "\(f) "
            let after = rest.dropFirst(2)
            if after.hasPrefix("[ ] ") || after.hasPrefix("[x] ") || after.hasPrefix("[X] ") { p += String(after.prefix(4)); n += "[ ] " }
            prefix = String(spaces) + p; next = String(spaces) + n; return
        }
        let digits = rest.prefix { $0.isNumber }
        let after = rest.dropFirst(digits.count)
        if !digits.isEmpty, digits.count <= 4, let p = after.first, p == "." || p == ")", after.dropFirst().first == " ", let n = Int(digits) {
            prefix = "\(spaces)\(digits)\(p) "; next = "\(spaces)\(n + 1)\(p) "; return
        }
        return nil
    }
}
