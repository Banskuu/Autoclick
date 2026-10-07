import Foundation

public enum ClockTools {
    public static func parseUTCOffset(_ text: String) -> Int? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        value = value.replacingOccurrences(of: "UTC", with: "")
        value = value.replacingOccurrences(of: " ", with: "")
        let pattern = #"^([+-]?)(\d{1,2})(?::(\d{1,2}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swift = Range(range, in: value) else { return nil }
            return String(value[swift])
        }
        let sign = group(1) ?? ""
        guard let hours = Int(group(2) ?? "") else { return nil }
        let minutes = Int(group(3) ?? "0") ?? 0
        guard hours <= 14, minutes <= 59 else { return nil }
        let total = hours * 60 + minutes
        guard total <= 840 else { return nil }
        return sign == "-" ? -total : total
    }

    public static func formatUTCOffset(_ minutes: Int) -> String {
        let clamped = min(840, max(-840, minutes))
        let sign = clamped < 0 ? "-" : "+"
        let value = abs(clamped)
        let h = value / 60
        let m = value % 60
        return m == 0 ? "UTC\(sign)\(h)" : String(format: "UTC%@%d:%02d", sign, h, m)
    }

    public static func displayDate(_ utc: Date, offsetMinutes: Int) -> Date {
        utc.addingTimeInterval(TimeInterval(offsetMinutes * 60))
    }

    public static func utcDate(fromDisplay date: Date, offsetMinutes: Int) -> Date {
        date.addingTimeInterval(TimeInterval(-offsetMinutes * 60))
    }

    public static func parseDisplayDate(date: String, time: String, offsetMinutes: Int) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let display = formatter.date(from: "\(date) \(time)") else { return nil }
        return utcDate(fromDisplay: display, offsetMinutes: offsetMinutes)
    }

    public static func displayStrings(utc: Date, offsetMinutes: Int) -> (date: String, time: String) {
        let display = displayDate(utc, offsetMinutes: offsetMinutes)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        timeFormatter.dateFormat = "HH:mm:ss"
        return (dateFormatter.string(from: display), timeFormatter.string(from: display))
    }
}
