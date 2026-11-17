import SwiftUI

struct CalendarHeader: View {
    let title: String
    let subtitle: String
    @Binding var mode: CalendarMode
    let isLoading: Bool
    let filterActive: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void
    let onFilter: () -> Void
    let onSettings: () -> Void

    @Namespace private var pill

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Chalk.display(32))
                        .chalk()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .contentTransition(.opacity)
                        .animation(Chalk.spring, value: title)
                    ChalkUnderlineView(seed: title.stableSeed)
                        .id(title)
                        .frame(width: 130, height: 8)
                    Text(subtitle)
                        .font(Chalk.font(14, relativeTo: .subheadline))
                        .chalk(Chalk.dim)
                        .contentTransition(.numericText())
                        .animation(Chalk.spring, value: subtitle)
                }
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView()
                        .tint(Chalk.white)
                        .frame(width: 38, height: 38)
                        .transition(.scale.combined(with: .opacity))
                }
                GlassIconButton(
                    systemName: filterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                    tint: filterActive ? Chalk.yellow : Chalk.white,
                    label: "Filter",
                    action: onFilter
                )
                GlassIconButton(systemName: "gearshape", label: "Settings", action: onSettings)
            }
            .animation(Chalk.spring, value: isLoading)

            HStack(spacing: 8) {
                modeSwitcher
                Spacer(minLength: 4)
                GlassIconButton(systemName: "chevron.left", label: "Previous", action: onPrev)
                Button("Today", action: onToday)
                    .buttonStyle(ChalkButtonStyle(color: Chalk.yellow))
                GlassIconButton(systemName: "chevron.right", label: "Next", action: onNext)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(CalendarMode.allCases) { m in
                Button {
                    withAnimation(Chalk.spring) { mode = m }
                } label: {
                    Text(m.title)
                        .font(Chalk.font(15, bold: true, relativeTo: .subheadline))
                        .foregroundStyle(mode == m ? Chalk.boardDeep : Chalk.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            if mode == m {
                                Capsule()
                                    .fill(Chalk.yellow.opacity(0.92))
                                    .matchedGeometryEffect(id: "mode", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())
        .sensoryFeedback(.selection, trigger: mode)
    }
}
