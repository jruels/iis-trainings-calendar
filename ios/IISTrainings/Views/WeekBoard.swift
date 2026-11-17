import SwiftUI

/// The weekly view. A strip of spanning bars on top for the shape of the
/// week, then every day with every class written out in full.
///
/// Narrow screens list the days top to bottom; wide screens (an unfolded
/// phone, iPad, landscape) lay them out as columns.
struct WeekBoard: View {
    let anchor: DayKey
    let trainings: [Training]
    let showWeekends: Bool
    let columns: Bool
    let selected: DayKey?
    let namespace: Namespace.ID
    let onSelect: (DayKey, String?) -> Void

    @State private var expanded: Set<String> = []

    var body: some View {
        let days = CalendarMath.visible(CalendarMath.week(containing: anchor), showWeekends: showWeekends)

        VStack(spacing: 14) {
            VStack(spacing: 0) {
                WeekdayHeader(showWeekends: showWeekends)
                WeekRow(
                    days: days,
                    month: nil,
                    layout: CalendarMath.layout(days: days, trainings: trainings),
                    selected: selected,
                    namespace: namespace,
                    isZoomSource: false,
                    onSelect: onSelect
                )
            }
            .padding(.horizontal, 6)

            if columns {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(days) { day in
                        daySection(day, compact: true)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(.horizontal, 10)
            } else {
                VStack(spacing: 18) {
                    ForEach(days) { day in
                        daySection(day, compact: false)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    @ViewBuilder
    private func daySection(_ day: DayKey, compact: Bool) -> some View {
        let list = CalendarMath.trainings(on: day, from: trainings)
        let isToday = day == .today

        VStack(alignment: .leading, spacing: 10) {
            Button {
                onSelect(day, nil)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(day.string(compact ? "EEE" : "EEEE"))
                        .font(Chalk.display(compact ? 16 : 21, relativeTo: .title3))
                        .chalk(isToday ? Chalk.yellow : Chalk.white)
                    Text(day.string("MMM d"))
                        .font(Chalk.font(compact ? 12 : 15, relativeTo: .subheadline))
                        .chalk(Chalk.dim)
                    Spacer(minLength: 0)
                    if !compact {
                        if !list.isEmpty { TallyMarks(count: min(list.count, 20), height: 11) }
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .chalk(Chalk.dim)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background {
                    if isToday || selected == day {
                        RoundedRectangle(cornerRadius: 10).fill(Chalk.yellow.opacity(0.08))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(ZoomSource(id: day, namespace: namespace, enabled: selected == nil))

            if list.isEmpty {
                Text("No classes")
                    .font(Chalk.font(13, relativeTo: .footnote))
                    .chalk(Chalk.white.opacity(0.35))
                    .padding(.leading, 8)
            } else {
                ForEach(list) { t in
                    let key = "\(day.id)|\(t.id)"
                    EventCard(
                        training: t,
                        day: day,
                        isExpanded: Binding(
                            get: { expanded.contains(key) },
                            set: { open in
                                if open { expanded.insert(key) } else { expanded.remove(key) }
                            }
                        ),
                        compact: compact
                    )
                }
            }
        }
    }
}
