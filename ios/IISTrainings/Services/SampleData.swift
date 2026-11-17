import Foundation

/// Made-up classes so the app looks alive before a token is added, and for
/// SwiftUI previews. Dates are relative to today.
enum SampleData {
    static func make(around anchor: DayKey = .today) -> [Training] {
        // Monday of the anchor's week (weekday 2 = Monday).
        let monday = anchor.adding(days: -((anchor.weekday + 5) % 7))
        func day(_ weekOffset: Int, _ weekday: Int) -> DayKey {
            // weekday: 0 = Monday ... 4 = Friday
            monday.adding(days: weekOffset * 7 + weekday)
        }

        let people: [(String, String)] = [
            ("Jason Smith", "#ff6d3b"), ("Ada Park", "#579bfc"), ("Ben Ortiz", "#9cd326"),
            ("Cleo Nash", "#ff5ac4"), ("Dev Rao", "#4eccc6"), ("Erin Holt", "#cab641"),
        ]
        let courses: [(String, String, String, String, String)] = [
            ("Kubernetes Introduction", "TEKsystems", "Acme Bank", "Virtual", "EST"),
            ("Modern Automation with Terraform and Ansible", "TEKsystems", "Globex", "Onsite", "CST"),
            ("AI-Powered Kubernetes Troubleshooting", "TEKsystems", "Initech", "Virtual", "PST"),
            ("Secure Coding in Python", "Direct", "Umbrella Health", "Hybrid", "EST"),
            ("Ansible Automation for Enterprise Teams", "TEKsystems", "Acme Bank", "Virtual", "Singapore"),
            ("GitHub Actions Deep Dive", "Direct", "Stark Industries", "Virtual", "London"),
            ("Platform Engineering Bootcamp", "TEKsystems", "Wayne Corp", "Virtual", "EST"),
            ("Docker Fundamentals", "Direct", "Hooli", "Onsite", "PST"),
        ]
        let statuses: [(String, String)] = [
            ("Scheduled", "#9d50dd"), ("Pre-Class", "#216edf"), ("In Progress", "#9cd326"), ("In Scheduling", "#fdab3d"),
        ]

        // (course, person, week offset, first weekday, length in weekdays, start hour)
        let plan: [(Int, Int, Int, Int, Int, Int)] = [
            (0, 0, 0, 0, 3, 9), (1, 1, 0, 0, 5, 9), (2, 2, 0, 1, 2, 8), (3, 3, 0, 2, 3, 10),
            (4, 0, 1, 0, 4, 9), (5, 4, 1, 1, 3, 9), (6, 5, 1, 0, 10, 9), (7, 2, 1, 3, 2, 13),
            (0, 3, -1, 0, 3, 9), (2, 1, -1, 2, 3, 9), (3, 0, 2, 0, 5, 9), (5, 2, 2, 1, 2, 9),
            (1, 4, 2, 2, 3, 9), (7, 1, 3, 0, 3, 9), (4, 3, 3, 1, 4, 9), (0, 5, -2, 1, 3, 9),
            (2, 0, -2, 0, 5, 9), (6, 4, -3, 0, 5, 9), (3, 2, 4, 0, 3, 9), (5, 0, 4, 2, 3, 9),
        ]

        return plan.enumerated().map { entry -> Training in
            let i = entry.offset
            let p = entry.element
            let course = courses[p.0]
            let person = people[p.1]
            let start = day(p.2, p.3)
            var end = start
            var remaining = p.4 - 1
            while remaining > 0 {
                end = end.adding(days: 1)
                if !end.isWeekend { remaining -= 1 }
            }
            let status = p.2 < 0 ? ("Completed", "#037f4c") : statuses[i % statuses.count]
            return Training(
                id: "sample-\(i)",
                itemID: "0",
                source: p.2 < 0 ? .completed : (p.0 == 6 ? .bootcamps : .trainings),
                group: status.0,
                name: "\(course.0) | \(course.1) | \(course.2) | \(course.3) - \(course.4)",
                segment: p.0 == 6 ? "Week \(max(1, p.2 + 4))" : nil,
                instructor: person.0,
                instructorHex: person.1,
                status: status.0,
                statusHex: status.1,
                start: start,
                end: end,
                startTime: ClockTime(hour: p.5, minute: 0),
                endTime: ClockTime(hour: p.5 + 8, minute: 0),
                timeZoneLabel: course.4,
                delivery: course.3,
                deliveryHex: course.3 == "Virtual" ? "#9cd326" : (course.3 == "Onsite" ? "#216edf" : "#9d50dd"),
                location: course.3 == "Virtual" ? "" : "Plano, TX, USA",
                opportunity: "OPP#-26-00\(23100 + i * 7)",
                customer: course.2,
                client: course.1,
                clientContact: "",
                confirmed: i % 3 != 0
            )
        }
    }
}
