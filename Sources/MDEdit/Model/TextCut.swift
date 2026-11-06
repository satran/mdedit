import Foundation

enum TextCut {
    /// Cuts to at most `bytes` of UTF-8 without splitting a character.
    static func cut(_ s: String, bytes: Int) -> (String, Bool) {
        guard s.utf8.count > bytes else { return (s, false) }
        return (decode(Data(s.utf8.prefix(bytes))), true)
    }

    /// The text of the start of a file: drops up to three trailing bytes that cut a character in two.
    static func decode(_ data: Data) -> String {
        var d = data
        var dropped = 0
        while !d.isEmpty, dropped < 4, String(data: d, encoding: .utf8) == nil { d.removeLast(); dropped += 1 }
        return String(decoding: d, as: UTF8.self)
    }
}
