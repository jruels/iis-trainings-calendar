import Foundation

/// A calendar day with no time or time zone attached.
///
/// Class dates on the monday boards are plain dates ("2026-12-07"), so the
/// app keeps them that way. All day math runs on a fixed UTC Gregorian
/// calendar, which makes it immune to DST jumps and device time zone changes.
struct DayKey: Hashable, Comparable, Codable, Sendable, Identifiable {
    let year: Int
    let month: Int
    let day: Int

    var id: Int { year * 10_000 + month * 100 + day }

    static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `timeZone` (defaults to the device zone).
    init(_ date: Date, in timeZone: TimeZone = .current) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Parses "YYYY-MM-DD".
    init?(iso: String) {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    static var today: DayKey { DayKey(Date()) }

    /// Midnight UTC of this day. Only meaningful together with `DayKey.utc`.
    var utcDate: Date {
        DayKey.utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    func adding(days n: Int) -> DayKey {
        guard n != 0, let d = DayKey.utc.date(byAdding: .day, value: n, to: utcDate) else { return self }
        return DayKey(d, in: DayKey.utc.timeZone)
    }

    func adding(months n: Int) -> DayKey {
        guard n != 0, let d = DayKey.utc.date(byAdding: .month, value: n, to: utcDate) else { return self }
        return DayKey(d, in: DayKey.utc.timeZone)
    }

    func days(until other: DayKey) -> Int {
        DayKey.utc.dateComponents([.day], from: utcDate, to: other.utcDate).day ?? 0
    }

    /// 1 = Sunday ... 7 = Saturday.
    var weekday: Int { DayKey.utc.component(.weekday, from: utcDate) }
    var isWeekend: Bool { weekday == 1 || weekday == 7 }

    var firstOfMonth: DayKey { DayKey(year: year, month: month, day: 1) }
    var lastOfMonth: DayKey { firstOfMonth.adding(months: 1).adding(days: -1) }

    func isSameMonth(as other: DayKey) -> Bool { year == other.year && month == other.month }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.id < rhs.id }

    // MARK: Formatting

    private static var formatterCache: [String: DateFormatter] = [:]
    private static let cacheLock = NSLock()

    /// Formats with a localized template, e.g. "EEEE", "MMM d", "MMMM y".
    func string(_ template: String) -> String {
        DayKey.cacheLock.lock()
        defer { DayKey.cacheLock.unlock() }
        let f: DateFormatter
        if let cached = DayKey.formatterCache[template] {
            f = cached
        } else {
            f = DateFormatter()
            f.calendar = DayKey.utc
            f.timeZone = DayKey.utc.timeZone
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate(template)
            DayKey.formatterCache[template] = f
        }
        return f.string(from: utcDate)
    }
}

/// A wall-clock time as stored in monday's Hour columns.
struct ClockTime: Hashable, Codable, Sendable, Comparable {
    let hour: Int
    let minute: Int

    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    var text: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return minute == 0 ? "\(h12) \(suffix)" : String(format: "%d:%02d %@", h12, minute, suffix)
    }
}
