import SwiftUI

struct MonthGrid: View {
    let month: DayKey
    let trainings: [Training]
    let showWeekends: Bool
    let selected: DayKey?
    let namespace: Namespace.ID
    let onSelect: (DayKey, String?) -> Void

    var body: some View {
        let weeks = CalendarMath.monthWeeks(containing: month)
        VStack(spacing: 0) {
            WeekdayHeader(showWeekends: showWeekends)
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let days = CalendarMath.visible(week, showWeekends: showWeekends)
                WeekRow(
                    days: days,
                    month: month,
                    layout: CalendarMath.layout(days: days, trainings: trainings),
                    selected: selected,
                    namespace: namespace,
                    isZoomSource: true,
                    rowIndex: index,
                    onSelect: onSelect
                )
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Chalk.line).frame(height: 1).offset(y: 24) }
        .padding(.horizontal, 6)
    }
}

struct WeekdayHeader: View {
    let showWeekends: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarMath.weekdaySymbols(showWeekends: showWeekends)) { item in
                Text(item.symbol.uppercased())
                    .font(Chalk.font(12, bold: true, relativeTo: .caption))
                    .chalk(item.weekday == 1 || item.weekday == 7 ? Chalk.dim.opacity(0.7) : Chalk.dim)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 24)
    }
}

/// One week of the month: day cells underneath, class bars on top. The row
/// is as tall as it needs to be to show every class.
struct WeekRow: View {
    let days: [DayKey]
    let month: DayKey?
    let layout: WeekLayout
    let selected: DayKey?
    let namespace: Namespace.ID
    var isZoomSource = true
    var rowIndex = 0
    let onSelect: (DayKey, String?) -> Void

    static let header: CGFloat = 28
    static let lane: CGFloat = 21
    static let laneGap: CGFloat = 3

    @State private var drawn = false

    private var height: CGFloat {
        max(66, Self.header + CGFloat(layout.laneCount) * (Self.lane + Self.laneGap) + 8)
    }

    var body: some View {
        GeometryReader { geo in
            let colW = geo.size.width / CGFloat(max(days.count, 1))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element) { col, day in
                        DayCell(
                            day: day,
                            inMonth: month.map { day.isSameMonth(as: $0) } ?? true,
                            isSelected: selected == day,
                            count: layout.count(on: col)
                        )
                        .frame(width: colW, height: height)
                        .contentShape(Rectangle())
                        .modifier(ZoomSource(id: day, namespace: namespace, enabled: isZoomSource))
                        .onTapGesture { onSelect(day, nil) }
                        .accessibilityAddTraits(.isButton)
                    }
                }

                ForEach(layout.bars) { bar in
                    let w = colW * CGFloat(bar.span) - 4
                    EventBar(bar: bar, width: w, compact: colW < 58)
                        .frame(width: w, height: Self.lane)
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            let col = bar.startColumn + min(bar.span - 1, max(0, Int(location.x / colW)))
                            onSelect(days[col], bar.training.id)
                        }
                        .scaleEffect(x: drawn ? 1 : 0.02, y: 1, anchor: .leading)
                        .opacity(drawn ? 1 : 0)
                        .animation(
                            .spring(response: 0.55, dampingFraction: 0.82)
                                .delay(Double(rowIndex) * 0.05 + Double(bar.startColumn) * 0.035 + Double(bar.lane) * 0.02),
                            value: drawn
                        )
                        .offset(x: colW * CGFloat(bar.startColumn) + 2,
                                y: Self.header + CGFloat(bar.lane) * (Self.lane + Self.laneGap))
                }
            }
        }
        .frame(height: height)
        .onAppear { drawn = true }
    }
}

struct DayCell: View {
    let day: DayKey
    let inMonth: Bool
    let isSelected: Bool
    let count: Int

    @State private var circled = false

    var body: some View {
        let isToday = day == .today
        ZStack(alignment: .topLeading) {
            Rectangle().fill(day.isWeekend ? Color.black.opacity(0.14) : Color.clear)

            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Chalk.yellow.opacity(0.08))
                    .overlay(SketchyRect(seed: UInt64(day.id), wobble: 1.2).stroke(Chalk.yellow.opacity(0.7), style: .chalk(1.4)))
                    .padding(2)
                    .transition(.opacity)
            }

            HStack(alignment: .center, spacing: 3) {
                Text("\(day.day)")
                    .font(Chalk.font(14, bold: isToday, relativeTo: .footnote))
                    .chalk(isToday ? Chalk.yellow : (inMonth ? Chalk.white : Chalk.white.opacity(0.3)))
                    .frame(minWidth: 22, minHeight: 22)
                    .background {
                        if isToday {
                            ChalkCircle(seed: UInt64(day.id))
                                .trim(from: 0, to: circled ? 1 : 0)
                                .stroke(Chalk.yellow, style: .chalk(1.8))
                                .padding(-3)
                        }
                    }
                Spacer(minLength: 0)
                if count > 10 {
                    Text("\(count)")
                        .font(Chalk.font(10, bold: true, relativeTo: .caption2))
                        .chalk(Chalk.dim)
                } else if count > 0 {
                    TallyMarks(count: count, height: 9)
                        .opacity(inMonth ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 5)
            .padding(.top, 3)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Chalk.line).frame(width: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Chalk.line).frame(height: 1) }
        .onAppear {
            if isToday { withAnimation(.easeOut(duration: 0.9).delay(0.35)) { circled = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.string("EEEE MMMM d")), \(count) \(count == 1 ? "class" : "classes")")
    }
}

/// A class drawn as a chalk bar across the days it meets this week.
struct EventBar: View {
    let bar: WeekBar
    let width: CGFloat
    var compact = false

    var body: some View {
        let t = bar.training
        let color = Chalk.tint(t.instructorHex, fallbackSeed: t.instructor)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: bar.continuesFromBefore ? 2 : 7,
            bottomLeadingRadius: bar.continuesFromBefore ? 2 : 7,
            bottomTrailingRadius: bar.continuesAfter ? 2 : 7,
            topTrailingRadius: bar.continuesAfter ? 2 : 7
        )

        HStack(spacing: 3) {
            if bar.continuesFromBefore && width > 40 {
                Image(systemName: "chevron.compact.left").font(.system(size: 9, weight: .heavy))
            }
            if width > 78, t.hasRealInstructor {
                Text(t.instructorInitials)
                    .font(Chalk.font(9, bold: true, relativeTo: .caption2))
                    .padding(.horizontal, 3)
                    .background(color.opacity(0.45), in: Capsule())
            }
            Text(t.displayTitle)
                .font(Chalk.font(compact ? 10 : 11, bold: true, relativeTo: .caption2))
                .lineLimit(1)
                .strikethrough(t.isCancelled)
            Spacer(minLength: 0)
            if bar.continuesAfter && width > 40 {
                Image(systemName: "chevron.compact.right").font(.system(size: 9, weight: .heavy))
            }
        }
        .padding(.horizontal, 5)
        .chalk(Chalk.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(shape.fill(color.opacity(t.isCancelled ? 0.12 : 0.32)))
        .overlay(
            shape.stroke(
                color.opacity(0.9),
                style: StrokeStyle(lineWidth: 1, dash: t.status.lowercased().contains("scheduling") ? [3, 2] : [])
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(t.displayTitle), \(t.instructor), \(t.status)")
        .accessibilityAddTraits(.isButton)
    }
}
