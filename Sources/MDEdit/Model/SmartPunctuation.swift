import Foundation

/// The viewer sets real punctuation: curly quotes, en and em dashes, true ellipses. Only the viewer: the text on disk is not changed,
/// and code, addresses and link targets are never touched.
enum SmartPunctuation {
    static func apply(_ s: String, previous: Character? = nil) -> String {
        guard s.contains(where: { "\"'.-".contains($0) }) else { return s }
        var out = ""
        var prev = previous
        let chars = Array(s)
        var i = 0
        func opens(_ before: Character?) -> Bool {
            guard let b = before else { return true }
            return b.isWhitespace || "([{<“‘—–/".contains(b)
        }
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "\"": out.append(opens(prev) ? "“" : "”")
            case "'":
                // an apostrophe or a closing quote after a word; an opening quote after a space, before a letter
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                out.append(opens(prev) && (next?.isLetter ?? false) ? "‘" : "’")
            case "." where i + 2 < chars.count + 0 && chars[i + 1] == "." && chars[i + 2] == ".":
                out.append("…"); i += 2
            case "-" where i + 2 < chars.count && chars[i + 1] == "-" && chars[i + 2] == "-":
                out.append("—"); i += 2
            case "-" where i + 1 < chars.count && chars[i + 1] == "-":
                out.append("–"); i += 1
            default: out.append(c)
            }
            prev = out.last
            i += 1
        }
        return out
    }
}
