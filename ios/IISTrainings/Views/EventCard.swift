import SwiftUI

/// A class written on the board. Tap to expand the full details in place.
struct EventCard: View {
    let training: Training
    let day: DayKey?
    @Binding var isExpanded: Bool
    var compact = false

    var body: some View {
        let t = training
        let color = Chalk.tint(t.instructorHex, fallbackSeed: t.instructor)
        let statusColor = Chalk.tint(t.statusHex, fallbackSeed: t.status)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(color)
                    .frame(width: 4)
                    .shadow(color: color.opacity(0.6), radius: 3)

                VStack(alignment: .leading, spacing: 5) {
                    Text(t.courseTitle)
                        .font(Chalk.font(compact ? 13 : 17, bold: true, relativeTo: .headline))
                        .chalk()
                        .strikethrough(t.isCancelled, color: Chalk.pink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let segment = t.segment {
                        Text(segment)
                            .font(Chalk.font(compact ? 11 : 13, relativeTo: .subheadline))
                            .chalk(Chalk.yellow)
                    }

                    Label(t.instructor.isEmpty ? "Unassigned" : t.instructor, systemImage: "person.fill")
                        .font(Chalk.font(compact ? 11 : 13, relativeTo: .subheadline))
                        .chalk(color)
                        .labelStyle(.titleAndIcon)

                    if !compact {
                        Label(t.classTimeText ?? "All day", systemImage: "clock")
                            .font(Chalk.font(13, relativeTo: .subheadline))
                            .chalk(Chalk.dim)
                        if !t.subtitle.isEmpty {
                            Text(t.subtitle)
                                .font(Chalk.font(12, relativeTo: .footnote))
                                .chalk(Chalk.dim)
                                .lineLimit(isExpanded ? nil : 1)
                        }
                    } else if let time = t.startTime {
                        Text(time.text + (t.timeZoneLabel.isEmpty ? "" : " \(t.timeZoneLabel)"))
                            .font(Chalk.font(11, relativeTo: .caption))
                            .chalk(Chalk.dim)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    if !compact, !t.status.isEmpty {
                        ChalkPill(text: t.status, color: statusColor)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .chalk(Chalk.dim)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                EventDetails(training: t, day: day, compact: compact)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .offset(y: -6)),
                        removal: .opacity
                    ))
            }
        }
        .padding(compact ? 10 : 14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Chalk.boardDeep.opacity(isExpanded ? 0.75 : 0.5))
                .overlay(RoundedRectangle(cornerRadius: 14).fill(color.opacity(isExpanded ? 0.12 : 0.05)))
        }
        .overlay(
            SketchyRect(seed: t.id.stableSeed, wobble: isExpanded ? 1.4 : 1.8)
                .stroke(color.opacity(isExpanded ? 0.85 : 0.5), style: .chalk(isExpanded ? 1.7 : 1.3))
        )
        .opacity(t.isCancelled ? 0.65 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Chalk.spring) { isExpanded.toggle() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
        .accessibilityElement(children: isExpanded ? .contain : .combine)
        .accessibilityHint(isExpanded ? "Collapses details" : "Shows details")
    }
}

/// Everything monday knows about a class.
struct EventDetails: View {
    let training: Training
    let day: DayKey?
    var compact = false

    var body: some View {
        let t = training
        VStack(alignment: .leading, spacing: 12) {
            ChalkUnderlineView(seed: t.id.stableSeed &+ 1, color: Chalk.faint, width: 1.5)
                .frame(height: 6)

            if let day, let s = t.session(on: day) {
                SessionProgress(training: t, current: day, index: s.index, total: s.total)
            }

            detailGrid(t)

            actionButtons(t)
        }
    }

    @ViewBuilder
    private func detailGrid(_ t: Training) -> some View {
        let sessions = t.sessionDays.count
        VStack(alignment: .leading, spacing: 10) {
            DetailRow(icon: "calendar", label: "Dates",
                      value: t.dateRangeText,
                      secondary: sessions > 1 ? "\(sessions) sessions" : nil)
            if let time = t.classTimeText {
                DetailRow(icon: "clock", label: "Class time", value: time,
                          secondary: day.flatMap { t.localTimeText(on: $0) })
            }
            DetailRow(icon: "person.crop.circle", label: "Instructor",
                      value: t.instructor.isEmpty ? "Unassigned" : t.instructor,
                      tint: Chalk.tint(t.instructorHex, fallbackSeed: t.instructor))
            if !t.status.isEmpty {
                DetailRow(icon: "flag", label: "Status", value: t.status,
                          tint: Chalk.tint(t.statusHex, fallbackSeed: t.status))
            }
            if !t.delivery.isEmpty {
                DetailRow(icon: deliveryIcon(t.delivery), label: "Delivery", value: t.delivery)
            }
            if !t.location.isEmpty {
                DetailRow(icon: "mappin.and.ellipse", label: "Location", value: t.location)
            }
            if !t.customer.isEmpty {
                DetailRow(icon: "building.2", label: "Customer", value: t.customer)
            }
            if !t.client.isEmpty {
                DetailRow(icon: "briefcase", label: "Client", value: t.client)
            }
            if !t.clientContact.isEmpty {
                DetailRow(icon: "person.text.rectangle", label: "Client contact", value: t.clientContact)
            }
            if !t.opportunity.isEmpty {
                DetailRow(icon: "number", label: "Opportunity", value: t.opportunity)
            }
            DetailRow(icon: t.confirmed ? "checkmark.seal.fill" : "seal", label: "Confirmed",
                      value: t.confirmed ? "Yes" : "Not yet",
                      tint: t.confirmed ? Chalk.green : Chalk.dim)
            DetailRow(icon: t.source.symbol, label: "Board",
                      value: t.group.isEmpty ? t.source.title : "\(t.source.title) · \(t.group)")
        }
    }

    @ViewBuilder
    private func actionButtons(_ t: Training) -> some View {
        let buttons = HStack(spacing: 8) {
            if let url = t.mondayURL, t.itemID != "0" {
                Link(destination: url) {
                    Label("Open in monday", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(ChalkButtonStyle(color: Chalk.yellow))
            }
            if !t.location.isEmpty,
               let q = t.location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let maps = URL(string: "https://maps.apple.com/?q=\(q)") {
                Link(destination: maps) {
                    Label("Map", systemImage: "map")
                }
                .buttonStyle(ChalkButtonStyle(color: Chalk.blue))
            }
            ShareLink(item: shareText(t)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ChalkButtonStyle(color: Chalk.green))
        }
        if compact {
            ScrollView(.horizontal, showsIndicators: false) { buttons }
        } else {
            ViewThatFits(in: .horizontal) {
                buttons
                ScrollView(.horizontal, showsIndicators: false) { buttons }
            }
        }
    }

    private func deliveryIcon(_ delivery: String) -> String {
        switch delivery.lowercased() {
        case "virtual": "video"
        case "onsite": "building.columns"
        case "hybrid": "rectangle.on.rectangle"
        default: "questionmark.circle"
        }
    }

    private func shareText(_ t: Training) -> String {
        var lines = [t.displayTitle, t.dateRangeText]
        if let time = t.classTimeText { lines.append(time) }
        if !t.instructor.isEmpty { lines.append("Instructor: \(t.instructor)") }
        if !t.customer.isEmpty { lines.append("Customer: \(t.customer)") }
        if !t.delivery.isEmpty { lines.append("Delivery: \(t.delivery)") }
        if !t.location.isEmpty { lines.append("Location: \(t.location)") }
        if let url = t.mondayURL, t.itemID != "0" { lines.append(url.absoluteString) }
        return lines.joined(separator: "\n")
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var secondary: String?
    var tint: Color = Chalk.white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .chalk(tint == Chalk.white ? Chalk.dim : tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(Chalk.font(10, bold: true, relativeTo: .caption2))
                    .chalk(Chalk.dim.opacity(0.8))
                Text(value)
                    .font(Chalk.font(15, relativeTo: .body))
                    .chalk(tint)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let secondary {
                    Text(secondary)
                        .font(Chalk.font(12, relativeTo: .footnote))
                        .chalk(Chalk.yellow.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Day 3 of 5" with a chalk dot for every session, filling in as it goes.
struct SessionProgress: View {
    let training: Training
    let current: DayKey
    let index: Int
    let total: Int

    @State private var filled = false

    var body: some View {
        let color = Chalk.tint(training.instructorHex, fallbackSeed: training.instructor)
        VStack(alignment: .leading, spacing: 6) {
            Text("Day \(index) of \(total)")
                .font(Chalk.font(13, bold: true, relativeTo: .subheadline))
                .chalk(Chalk.yellow)
            if total <= 30 {
                HStack(spacing: 5) {
                    ForEach(1...max(total, 1), id: \.self) { i in
                        Circle()
                            .fill(i < index ? color.opacity(0.85) : (i == index ? Chalk.yellow : Color.clear))
                            .overlay(Circle().strokeBorder(i == index ? Chalk.yellow : color.opacity(0.6), lineWidth: 1.2))
                            .frame(width: i == index ? 11 : 8, height: i == index ? 11 : 8)
                            .scaleEffect(filled ? 1 : 0.2)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(Double(i) * 0.03), value: filled)
                    }
                }
            } else {
                GeometryReader { geo in
                    Capsule().fill(Chalk.faint)
                        .overlay(alignment: .leading) {
                            Capsule().fill(color)
                                .frame(width: filled ? geo.size.width * CGFloat(index) / CGFloat(total) : 0)
                        }
                }
                .frame(height: 6)
                .animation(.easeOut(duration: 0.8), value: filled)
            }
        }
        .onAppear { filled = true }
    }
}
