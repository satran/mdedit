import Foundation

/// Dates in templates are plain text: `2026-11-06`, or `2026-11-06 14:30`. `today` and `now` are set once per render, in the local time zone.
enum TemplateDates {
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }
    private static let dateRegex = try! NSRegularExpression(pattern: "^(\\d{4})-(\\d{2})-(\\d{2})(?:[T ](\\d{2}):(\\d{2}))?")

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.dateFormat = pattern
        return f
    }

    static func today(_ now: Date) -> String { formatter("yyyy-MM-dd").string(from: now) }
    static func nowText(_ now: Date) -> String { formatter("yyyy-MM-dd HH:mm").string(from: now) }

    /// The date (and time, if there is one) at the start of the text; nil when it is not a real date.
    static func parse(_ s: String) -> Date? {
        let ns = s as NSString
        guard let m = dateRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func n(_ i: Int) -> Int? { m.range(at: i).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: i))) }
        var c = DateComponents()
        c.year = n(1); c.month = n(2); c.day = n(3); c.hour = n(4) ?? 0; c.minute = n(5) ?? 0
        guard let d = calendar.date(from: c), calendar.dateComponents([.year, .month, .day], from: d).day == c.day,
              calendar.dateComponents([.year, .month, .day], from: d).month == c.month else { return nil }
        return d
    }

    /// Whole calendar days from `from` to `to`.
    static func days(from: Date, to: Date) -> Int {
        let c = calendar
        return c.dateComponents([.day], from: c.startOfDay(for: from), to: c.startOfDay(for: to)).day ?? 0
    }

    /// `2026-W45`: the ISO week, so weeks sort and compare across years.
    static func week(_ d: Date) -> String {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        let parts = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    /// An ICU date pattern such as `EEE d MMM` (Mon 2 Nov). Only letters, digits, spaces and `- / . , :` are allowed, up to 40 characters.
    static func format(_ d: Date, pattern: String) -> String? {
        guard pattern.count <= 40, pattern.unicodeScalars.allSatisfy({ ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) || " -/.,:".unicodeScalars.contains($0) }) else { return nil }
        return formatter(pattern).string(from: d)
    }
}
