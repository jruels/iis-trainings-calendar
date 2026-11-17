import SwiftUI

/// The zoomed-in day: every class that meets, in time order, each one
/// expandable. Swipe sideways (or use the arrows) to move between days.
struct DayContent: View {
    @Binding var day: DayKey
    @Binding var focus: String?
    let trainings: [Training]
    let showWeekends: Bool

    @State private var expanded: Set<String> = []
    @State private var forward = true

    var body: some View {
        let list = CalendarMath.trainings(on: day, from: trainings)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DayHeader(day: day, count: list.count, onStep: step)

                    if list.contains(where: { !$0.isAllDay }) {
                        DayTimeline(trainings: list, day: day)
                    }

                    if list.isEmpty {
                        EmptyDay(day: day)
                    } else {
                        ForEach(list) { t in
                            EventCard(training: t, day: day, isExpanded: binding(for: t.id))
                                .id(t.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
                .id(day)
                .pageTransition(forward: forward)
            }
            .scrollIndicators(.hidden)
            .pagingSwipe { step($0) }
            .onAppear { openFocus(proxy) }
            .onChange(of: focus) { _, _ in openFocus(proxy) }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func openFocus(_ proxy: ScrollViewProxy) {
        guard let id = focus else { return }
        withAnimation(Chalk.spring) { _ = expanded.insert(id) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(Chalk.spring) { proxy.scrollTo(id, anchor: .top) }
        }
    }

    private func step(_ n: Int) {
        var next = day.adding(days: n)
        if !showWeekends {
            while next.isWeekend { next = next.adding(days: n > 0 ? 1 : -1) }
        }
        withAnimation(Chalk.spring) {
            forward = n > 0
            day = next
            focus = nil
            expanded.removeAll()
        }
    }
}

struct DayHeader: View {
    let day: DayKey
    let count: Int
    let onStep: (Int) -> Void

    var body: some View {
        let isToday = day == .today
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isToday ? "Today" : day.string("EEEE"))
                        .font(Chalk.display(30))
                        .chalk(isToday ? Chalk.yellow : Chalk.white)
                    Text(day.string(isToday ? "EEEE, MMMM d" : "MMMM d, y"))
                        .font(Chalk.font(16, relativeTo: .headline))
                        .chalk(Chalk.dim)
                }
                Spacer()
                GlassIconButton(systemName: "chevron.left", label: "Previous day") { onStep(-1) }
                GlassIconButton(systemName: "chevron.right", label: "Next day") { onStep(1) }
            }
            ChalkUnderlineView(seed: UInt64(day.id))
                .id(day)
                .frame(width: 160, height: 8)
            HStack(spacing: 8) {
                Text(count == 0 ? "Nothing scheduled" : "\(count) \(count == 1 ? "class" : "classes")")
                    .font(Chalk.font(14, bold: true, relativeTo: .subheadline))
                    .chalk(Chalk.white)
                if count > 0 { TallyMarks(count: min(count, 30), color: Chalk.white, height: 12) }
            }
        }
        .padding(.top, 8)
    }
}

/// A chalk ruler of the day in the device's local time, with one line per
/// class, so overlaps and time-zone shifts are obvious at a glance.
struct DayTimeline: View {
    let trainings: [Training]
    let day: DayKey

    @State private var drawn = false

    private struct Item: Identifiable {
        let id: String
        let start: Double
        let end: Double
        let color: Color
        let title: String
    }

    var body: some View {
        let items = makeItems()
        let lo = max(-12, floor(min(7, items.map(\.start).min() ?? 7)))
        let hi = min(36, ceil(max(19, items.map(\.end).max() ?? 19)))
        let stepHours = (hi - lo) > 16 ? 3.0 : 2.0
        let rowH: CGFloat = 12

        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR TIME · \(TimeZone.current.abbreviation() ?? "")")
                .font(Chalk.font(10, bold: true, relativeTo: .caption2))
                .chalk(Chalk.dim.opacity(0.8))
            GeometryReader { geo in
                let scale = geo.size.width / CGFloat(hi - lo)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stride(from: lo, through: hi, by: stepHours)), id: \.self) { h in
                        Rectangle()
                            .fill(Chalk.line)
                            .frame(width: 1, height: geo.size.height)
                            .offset(x: CGFloat(h - lo) * scale)
                        Text(hourLabel(h))
                            .font(Chalk.font(9, relativeTo: .caption2))
                            .chalk(Chalk.dim)
                            .fixedSize()
                            .offset(x: CGFloat(h - lo) * scale + 2, y: 0)
                    }

                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        Capsule()
                            .fill(item.color.opacity(0.85))
                            .frame(width: max(6, CGFloat(item.end - item.start) * scale), height: 6)
                            .shadow(color: item.color.opacity(0.6), radius: 2)
                            .scaleEffect(x: drawn ? 1 : 0.01, y: 1, anchor: .leading)
                            .animation(.easeOut(duration: 0.6).delay(0.1 + Double(i) * 0.06), value: drawn)
                            .offset(x: CGFloat(item.start - lo) * scale, y: 16 + CGFloat(i) * rowH)
                            .accessibilityLabel(item.title)
                    }

                    if day == .today {
                        let now = hoursSinceLocalMidnight(Date())
                        if now >= lo, now <= hi {
                            Rectangle()
                                .fill(Chalk.pink)
                                .frame(width: 2, height: geo.size.height - 12)
                                .offset(x: CGFloat(now - lo) * scale, y: 12)
                                .shadow(color: Chalk.pink, radius: 3)
                        }
                    }
                }
            }
            .frame(height: 20 + CGFloat(items.count) * rowH)
        }
        .padding(12)
        .background(Chalk.boardDeep.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(SketchyRect(seed: 404, wobble: 1.2).stroke(Chalk.faint, style: .chalk(1.2)))
        .onAppear { drawn = true }
    }

    private func makeItems() -> [Item] {
        guard let midnight = localMidnight() else { return [] }
        return trainings.compactMap { t in
            guard let iv = t.interval(on: day) else { return nil }
            return Item(
                id: t.id,
                start: iv.start.timeIntervalSince(midnight) / 3600,
                end: iv.end.timeIntervalSince(midnight) / 3600,
                color: Chalk.tint(t.instructorHex, fallbackSeed: t.instructor),
                title: t.displayTitle
            )
        }
    }

    private func localMidnight() -> Date? {
        Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
    }

    private func hoursSinceLocalMidnight(_ date: Date) -> Double {
        guard let m = localMidnight() else { return 0 }
        return date.timeIntervalSince(m) / 3600
    }

    private func hourLabel(_ h: Double) -> String {
        let hour = ((Int(h) % 24) + 24) % 24
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12)\(hour < 12 ? "a" : "p")"
    }
}

struct EmptyDay: View {
    let day: DayKey
    @State private var drawn = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: day.isWeekend ? "sun.max" : "cup.and.saucer")
                .font(.system(size: 44, weight: .light))
                .chalk(Chalk.yellow.opacity(0.8))
                .scaleEffect(drawn ? 1 : 0.6)
                .rotationEffect(.degrees(drawn ? 0 : -12))
            Text(day.isWeekend ? "Weekend. The board is clean." : "No classes. Recess!")
                .font(Chalk.display(18, relativeTo: .title3))
                .chalk(Chalk.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) { drawn = true } }
    }
}
