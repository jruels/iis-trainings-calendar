import SwiftUI

/// Where a tap on the calendar zooms to: a day, optionally with one class
/// already opened.
struct DayRoute: Hashable {
    let day: DayKey
    let focus: String?
}

struct RootView: View {
    @Environment(TrainingStore.self) private var store

    @AppStorage(Prefs.myName) private var myName = "Jason Smith"
    @AppStorage(Prefs.showWeekends) private var showWeekends = false
    @AppStorage(Prefs.hideCancelled) private var hideCancelled = true
    @AppStorage(Prefs.includeCompleted) private var includeCompleted = true
    @AppStorage(Prefs.instructorFilter) private var instructorFilter = ""
    @AppStorage(Prefs.mode) private var modeRaw = CalendarMode.month.rawValue

    @State private var search = ""
    @State private var anchor = DayKey.today
    @State private var forward = true
    @State private var path: [DayRoute] = []

    // Second pane on wide / unfolded screens.
    @State private var paneDay = DayKey.today
    @State private var paneFocus: String?

    @State private var showSettings = false
    @State private var showFilters = false
    @Namespace private var zoom

    private var mode: CalendarMode { CalendarMode(rawValue: modeRaw) ?? .month }

    private var filter: TrainingFilter {
        TrainingFilter(
            instructor: instructorFilter,
            myName: myName,
            hideCancelled: hideCancelled,
            includeCompleted: includeCompleted,
            search: search
        )
    }

    var body: some View {
        let visible = filter.apply(store.trainings)

        GeometryReader { geo in
            // Unfolded foldables, dual-screen phones, iPad and landscape
            // get the calendar on one half and the zoomed day on the other.
            let dual = geo.size.width >= 700
            NavigationStack(path: $path) {
                Group {
                    if dual {
                        HStack(spacing: 0) {
                            calendarPane(visible: visible, width: geo.size.width * 0.57 - 11, dual: true)
                            ChalkHinge()
                            DayContent(day: $paneDay, focus: $paneFocus, trainings: visible, showWeekends: showWeekends)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        calendarPane(visible: visible, width: geo.size.width, dual: false)
                    }
                }
                .background(ChalkboardBackground())
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: DayRoute.self) { route in
                    DayScreen(route: route, trainings: visible, showWeekends: showWeekends)
                        .navigationTransition(.zoom(sourceID: route.day, in: zoom))
                }
            }
            .onChange(of: dual) { _, isDual in
                // Unfolding mid-zoom: move the zoomed day into the side pane.
                if isDual, let last = path.last {
                    paneDay = last.day
                    paneFocus = last.focus
                    path.removeAll()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(
                instructorFilter: $instructorFilter,
                search: $search,
                hideCancelled: $hideCancelled,
                includeCompleted: $includeCompleted,
                showWeekends: $showWeekends,
                myName: myName
            )
            .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.selection, trigger: anchor)
    }

    // MARK: Calendar pane

    @ViewBuilder
    private func calendarPane(visible: [Training], width: CGFloat, dual: Bool) -> some View {
        VStack(spacing: 8) {
            CalendarHeader(
                title: title,
                subtitle: subtitle(visible: visible),
                mode: Binding(get: { mode }, set: { modeRaw = $0.rawValue }),
                isLoading: store.isLoading,
                filterActive: filter.isActive,
                onPrev: { page(-1) },
                onNext: { page(1) },
                onToday: goToday,
                onFilter: { showFilters = true },
                onSettings: { showSettings = true }
            )

            if store.isSampleData {
                Banner(icon: "sparkles", text: "Showing sample classes. Add your monday API token to load the real Calendar boards.",
                       actionTitle: "Connect", action: { showSettings = true })
            } else if let error = store.lastError {
                Banner(icon: "exclamationmark.triangle", text: error, color: Chalk.pink,
                       actionTitle: "Retry", action: { Task { await store.refresh() } })
            }

            ScrollView {
                ZStack(alignment: .top) {
                    switch mode {
                    case .month:
                        MonthGrid(
                            month: anchor,
                            trainings: visible,
                            showWeekends: showWeekends,
                            selected: dual ? paneDay : nil,
                            namespace: zoom,
                            onSelect: { select($0, focus: $1, dual: dual) }
                        )
                        .id("m\(anchor.year)-\(anchor.month)-\(store.revision)")
                        .pageTransition(forward: forward)
                    case .week:
                        WeekBoard(
                            anchor: anchor,
                            trainings: visible,
                            showWeekends: showWeekends,
                            columns: width >= 640,
                            selected: dual ? paneDay : nil,
                            namespace: zoom,
                            onSelect: { select($0, focus: $1, dual: dual) }
                        )
                        .id("w\(CalendarMath.startOfWeek(anchor).id)-\(store.revision)")
                        .pageTransition(forward: forward)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refresh() }
            .pagingSwipe { page($0) }
        }
        .frame(width: width)
        .animation(Chalk.spring, value: store.isSampleData)
        .animation(Chalk.spring, value: store.lastError)
    }

    // MARK: Titles

    private var title: String {
        switch mode {
        case .month:
            return anchor.string("MMMM")
        case .week:
            let days = CalendarMath.week(containing: anchor)
            let first = days.first!, last = days.last!
            return first.month == last.month
                ? "\(first.string("MMM d"))–\(last.day)"
                : "\(first.string("MMM d")) – \(last.string("MMM d"))"
        }
    }

    private func subtitle(visible: [Training]) -> String {
        let days: [DayKey]
        switch mode {
        case .month: days = CalendarMath.monthWeeks(containing: anchor).flatMap { $0 }.filter { $0.isSameMonth(as: anchor) }
        case .week: days = CalendarMath.week(containing: anchor)
        }
        guard let first = days.first, let last = days.last else { return "" }
        let count = visible.filter { $0.end >= first && $0.start <= last }.count
        let year = mode == .month ? anchor.string("y") : CalendarMath.week(containing: anchor).last!.string("y")
        return "\(year) · \(count) \(count == 1 ? "class" : "classes")"
    }

    // MARK: Actions

    private func page(_ step: Int) {
        withAnimation(Chalk.spring) {
            forward = step > 0
            switch mode {
            case .month: anchor = anchor.firstOfMonth.adding(months: step)
            case .week: anchor = anchor.adding(days: 7 * step)
            }
        }
    }

    private func goToday() {
        let today = DayKey.today
        withAnimation(Chalk.spring) {
            forward = today >= anchor
            anchor = today
            paneDay = today
            paneFocus = nil
        }
    }

    private func select(_ day: DayKey, focus: String?, dual: Bool) {
        if dual {
            withAnimation(Chalk.spring) {
                paneDay = day
                paneFocus = focus
            }
        } else {
            path.append(DayRoute(day: day, focus: focus))
        }
    }
}

/// The zoomed-in day on a single (folded) screen.
struct DayScreen: View {
    let route: DayRoute
    let trainings: [Training]
    let showWeekends: Bool

    @State private var day: DayKey
    @State private var focus: String?

    init(route: DayRoute, trainings: [Training], showWeekends: Bool) {
        self.route = route
        self.trainings = trainings
        self.showWeekends = showWeekends
        _day = State(initialValue: route.day)
        _focus = State(initialValue: route.focus)
    }

    var body: some View {
        DayContent(day: $day, focus: $focus, trainings: trainings, showWeekends: showWeekends)
            .background(ChalkboardBackground())
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(day.string("MMM y"))
                        .font(Chalk.font(15, bold: true, relativeTo: .headline))
                        .chalk(Chalk.dim)
                }
            }
    }
}
