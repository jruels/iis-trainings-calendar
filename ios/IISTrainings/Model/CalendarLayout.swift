import Foundation

enum CalendarMode: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }
    var title: String { self == .week ? "Week" : "Month" }
}

/// A class drawn as one continuous chalk bar inside a single week row.
struct WeekBar: Identifiable, Hashable {
    let training: Training
    let startColumn: Int
    let endColumn: Int
    let lane: Int
    /// The class started before this bar's first visible day.
    let continuesFromBefore: Bool
    /// The class goes on after this bar's last visible day.
    let continuesAfter: Bool

    var id: String { "\(training.id)-\(startColumn)" }
    var span: Int { endColumn - startColumn + 1 }
}

struct WeekLayout {
    let days: [DayKey]
    let bars: [WeekBar]
    let laneCount: Int

    func count(on column: Int) -> Int {
        bars.filter { $0.startColumn <= column && $0.endColumn >= column }.count
    }
}

struct WeekdaySymbol: Identifiable {
    let weekday: Int
    let symbol: String
    var id: Int { weekday }
}

enum CalendarMath {
    static var firstWeekday: Int { Calendar.current.firstWeekday }

    static func startOfWeek(_ day: DayKey) -> DayKey {
        let diff = (day.weekday - firstWeekday + 7) % 7
        return day.adding(days: -diff)
    }

    static func week(containing day: DayKey) -> [DayKey] {
        let start = startOfWeek(day)
        return (0..<7).map { start.adding(days: $0) }
    }

    /// Full weeks covering the month that contains `day`.
    static func monthWeeks(containing day: DayKey) -> [[DayKey]] {
        let last = day.lastOfMonth
        var cursor = startOfWeek(day.firstOfMonth)
        var weeks: [[DayKey]] = []
        while cursor <= last {
            weeks.append((0..<7).map { cursor.adding(days: $0) })
            cursor = cursor.adding(days: 7)
        }
        return weeks
    }

    static func visible(_ days: [DayKey], showWeekends: Bool) -> [DayKey] {
        showWeekends ? days : days.filter { !$0.isWeekend }
    }

    /// Weekday symbols in display order, optionally without Sat/Sun.
    static func weekdaySymbols(showWeekends: Bool) -> [WeekdaySymbol] {
        let symbols = Calendar.current.shortWeekdaySymbols
        return (0..<7)
            .map { (firstWeekday - 1 + $0) % 7 + 1 }
            .filter { showWeekends || ($0 != 1 && $0 != 7) }
            .map { WeekdaySymbol(weekday: $0, symbol: symbols[$0 - 1]) }
    }

    /// Packs every class that meets during `days` into lanes so each one
    /// is a single unbroken bar per run of consecutive meeting days, and no
    /// two bars overlap. Lanes grow without limit: the row auto-expands to
    /// show every class instead of hiding them behind "+3 more".
    static func layout(days: [DayKey], trainings: [Training]) -> WeekLayout {
        guard let first = days.first, let last = days.last else {
            return WeekLayout(days: days, bars: [], laneCount: 0)
        }

        struct Run { let training: Training; let start: Int; let end: Int }
        var runs: [Run] = []

        for t in trainings where t.end >= first && t.start <= last {
            var c = 0
            while c < days.count {
                if t.occurs(on: days[c]) {
                    let s = c
                    while c + 1 < days.count, t.occurs(on: days[c + 1]) { c += 1 }
                    runs.append(Run(training: t, start: s, end: c))
                }
                c += 1
            }
        }

        runs.sort { a, b in
            if a.start != b.start { return a.start < b.start }
            let la = a.end - a.start, lb = b.end - b.start
            if la != lb { return la > lb }
            if a.training.start != b.training.start { return a.training.start < b.training.start }
            return a.training.displayTitle < b.training.displayTitle
        }

        var laneEnds: [Int] = []
        var bars: [WeekBar] = []
        for run in runs {
            let lane: Int
            if let free = laneEnds.firstIndex(where: { $0 < run.start }) {
                lane = free
                laneEnds[free] = run.end
            } else {
                lane = laneEnds.count
                laneEnds.append(run.end)
            }
            bars.append(WeekBar(
                training: run.training,
                startColumn: run.start,
                endColumn: run.end,
                lane: lane,
                continuesFromBefore: run.training.start < days[run.start],
                continuesAfter: run.training.end > days[run.end]
            ))
        }
        return WeekLayout(days: days, bars: bars, laneCount: laneEnds.count)
    }

    /// Classes meeting on `day`, earliest first.
    static func trainings(on day: DayKey, from all: [Training]) -> [Training] {
        all.filter { $0.occurs(on: day) }
            .sorted {
                let a = $0.sortKey(on: day), b = $1.sortKey(on: day)
                return a != b ? a < b : $0.displayTitle < $1.displayTitle
            }
    }
}

/// Deterministic hash so chalk wobble stays put between launches.
extension String {
    var stableSeed: UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }
}
