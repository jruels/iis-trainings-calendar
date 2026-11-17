import Foundation

/// The monday boards that make up the Calendar.
enum SourceBoard: String, Codable, CaseIterable, Sendable, Identifiable {
    case trainings
    case bootcamps
    case completed

    var id: String { rawValue }

    var boardID: String {
        switch self {
        case .trainings: "18402638125"
        case .bootcamps: "18407475639"
        case .completed: "18408627394"
        }
    }

    var title: String {
        switch self {
        case .trainings: "Trainings"
        case .bootcamps: "Bootcamps / Multi-Instructor"
        case .completed: "Completed Courses"
        }
    }

    var symbol: String {
        switch self {
        case .trainings: "graduationcap"
        case .bootcamps: "figure.run"
        case .completed: "checkmark.seal"
        }
    }
}

/// One class (or one bootcamp segment) as it appears on the calendar.
struct Training: Identifiable, Hashable, Codable, Sendable {
    /// Unique per calendar entry. Bootcamp segments use the subitem id.
    var id: String
    /// The monday item ("pulse") to open. For a segment, the parent course.
    var itemID: String
    var source: SourceBoard
    var group: String

    /// Full monday item name, e.g. "Kubernetes Intro | TEKsystems | BofA | Virtual - EST".
    var name: String
    /// Bootcamp segment label, e.g. "Week 3", when this is a subitem.
    var segment: String?

    var instructor: String
    var instructorHex: String?
    var status: String
    var statusHex: String?

    var start: DayKey
    var end: DayKey
    var startTime: ClockTime?
    var endTime: ClockTime?
    var timeZoneLabel: String

    var delivery: String
    var deliveryHex: String?
    var location: String
    var opportunity: String
    var customer: String
    var client: String
    var clientContact: String
    var confirmed: Bool

    // MARK: Title parts

    private var nameParts: [String] {
        name.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// "Kubernetes Introduction"
    var courseTitle: String { nameParts.first ?? name }

    /// "TEKsystems · BofA · Virtual - EST"
    var subtitle: String { nameParts.dropFirst().joined(separator: " · ") }

    var displayTitle: String {
        if let segment, !segment.isEmpty { return "\(courseTitle) · \(segment)" }
        return courseTitle
    }

    var mondayURL: URL? {
        URL(string: "https://innovativeio-company.monday.com/boards/\(source.boardID)/pulses/\(itemID)")
    }

    // MARK: Status helpers

    var isCancelled: Bool {
        let s = status.lowercased()
        return s.contains("cancel")
    }

    var isPendingReschedule: Bool { status.lowercased().contains("reschedule") }

    var hasRealInstructor: Bool { !Training.nonPersonLabels.contains(instructor.lowercased()) }

    static let nonPersonLabels: Set<String> = [
        "", "unassigned", "requested dates", "tentative", "holiday", "cancelled",
        "pending reschedule", "multiple instructors", "multiple instructros",
        "bootcamp/mulit-instructor", "bootcamp/multi-instructor",
    ]

    var instructorInitials: String {
        guard hasRealInstructor else { return "?" }
        let letters = instructor.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    // MARK: Occurrence

    /// Ranges that sit entirely on a weekend are shown as-is; otherwise the
    /// class meets on weekdays only, matching the boards' "hide weekends"
    /// timeline setting.
    var meetsOnWeekends: Bool {
        // Any span of three or more days contains a weekday.
        guard start.days(until: end) < 2 else { return false }
        return start.isWeekend && end.isWeekend
    }

    func occurs(on day: DayKey) -> Bool {
        guard day >= start, day <= end else { return false }
        return !day.isWeekend || meetsOnWeekends
    }

    var sessionDays: [DayKey] {
        var out: [DayKey] = []
        var d = start
        let weekends = meetsOnWeekends
        while d <= end, out.count < 400 {
            if !d.isWeekend || weekends { out.append(d) }
            d = d.adding(days: 1)
        }
        return out
    }

    /// (1-based session number, total sessions) for `day`.
    func session(on day: DayKey) -> (index: Int, total: Int)? {
        let days = sessionDays
        guard let i = days.firstIndex(of: day) else { return nil }
        return (i + 1, days.count)
    }

    var dateRangeText: String {
        if start == end { return start.string("EEE MMM d, y") }
        if start.year == end.year {
            return "\(start.string("EEE MMM d")) – \(end.string("EEE MMM d, y"))"
        }
        return "\(start.string("MMM d, y")) – \(end.string("MMM d, y"))"
    }

    // MARK: Time

    var timeZone: TimeZone? { TimeZoneMap.zone(for: timeZoneLabel) }

    var isAllDay: Bool { startTime == nil || endTime == nil }

    /// "9 AM – 5 PM EST" in the class's own zone.
    var classTimeText: String? {
        guard let s = startTime, let e = endTime else { return nil }
        let zone = timeZoneLabel.isEmpty ? "" : " \(timeZoneLabel)"
        return "\(s.text) – \(e.text)\(zone)"
    }

    /// Absolute start/end for a given session day, using the class zone
    /// (falls back to the device zone when the board has none).
    func interval(on day: DayKey) -> DateInterval? {
        guard let s = startTime, let e = endTime else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone ?? .current
        guard
            let a = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: s.hour, minute: s.minute)),
            var b = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: e.hour, minute: e.minute))
        else { return nil }
        if b <= a { b = a.addingTimeInterval(3600) }
        return DateInterval(start: a, end: b)
    }

    /// "6 – 2 PM your time" when the class zone differs from the device zone.
    func localTimeText(on day: DayKey) -> String? {
        guard let tz = timeZone, let iv = interval(on: day) else { return nil }
        if tz.secondsFromGMT(for: iv.start) == TimeZone.current.secondsFromGMT(for: iv.start) { return nil }
        let f = DateFormatter()
        f.timeZone = .current
        f.dateFormat = "h:mm a"
        var text = "\(f.string(from: iv.start)) – \(f.string(from: iv.end))"
        let localDay = DayKey(iv.start)
        if localDay != day { text += " (\(localDay.string("EEE")))" }
        return text + " your time"
    }

    /// Sort key for a day list: timed classes by local start, all-day first.
    func sortKey(on day: DayKey) -> Double {
        interval(on: day)?.start.timeIntervalSince1970 ?? 0
    }
}

enum TimeZoneMap {
    /// Every Timezone dropdown label used across the three boards.
    static let identifiers: [String: String] = [
        "est": "America/New_York", "edt": "America/New_York", "us eastern": "America/New_York",
        "cst": "America/Chicago", "cdt": "America/Chicago", "us central": "America/Chicago",
        "mst": "America/Denver", "mdt": "America/Denver", "us mountain": "America/Denver",
        "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "us pacific": "America/Los_Angeles",
        "utc": "UTC",
        "london": "Europe/London", "europe western": "Europe/London",
        "paris": "Europe/Paris", "cet": "Europe/Paris", "europe central": "Europe/Paris",
        "europe eastern": "Europe/Bucharest",
        "india": "Asia/Kolkata", "ist": "Asia/Kolkata",
        "singapore": "Asia/Singapore", "asia pacific": "Asia/Singapore",
    ]

    static func zone(for label: String) -> TimeZone? {
        let key = label.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        guard let id = identifiers[key] else { return nil }
        return TimeZone(identifier: id)
    }
}
