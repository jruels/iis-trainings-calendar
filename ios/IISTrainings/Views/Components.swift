import SwiftUI

/// Chalk-outlined capsule button.
struct ChalkButtonStyle: ButtonStyle {
    var color: Color = Chalk.white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Chalk.font(14, bold: true, relativeTo: .subheadline))
            .chalk(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(configuration.isPressed ? 0.2 : 0.08), in: Capsule())
            .overlay(SketchyRect(seed: 5, wobble: 1, overshoot: 2).stroke(color.opacity(0.55), style: .chalk(1.2)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round icon button on a Liquid Glass puck.
struct GlassIconButton: View {
    let systemName: String
    var tint: Color = Chalk.white
    var label: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .chalk(tint)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(label.isEmpty ? systemName : label)
    }
}

/// An underline that draws itself in when it appears.
struct ChalkUnderlineView: View {
    var seed: UInt64 = 11
    var color: Color = Chalk.yellow
    var width: CGFloat = 2
    @State private var drawn = false

    var body: some View {
        ChalkUnderline(seed: seed)
            .trim(from: 0, to: drawn ? 1 : 0)
            .stroke(color.opacity(0.85), style: .chalk(width))
            .onAppear {
                withAnimation(.easeOut(duration: 0.7).delay(0.1)) { drawn = true }
            }
    }
}

/// A vertical chalk line, used as the fold between the two halves of a
/// foldable / dual-screen layout.
struct ChalkHinge: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                var rng = SeededRandom(seed: 99)
                let x = geo.size.width / 2
                p.move(to: CGPoint(x: x, y: 12))
                var y: CGFloat = 12
                while y < geo.size.height - 12 {
                    y += 40
                    p.addLine(to: CGPoint(x: x + rng.signed() * 1.2, y: min(y, geo.size.height - 12)))
                }
            }
            .stroke(Chalk.faint, style: .chalk(1.5))
        }
        .frame(width: 22)
        .accessibilityHidden(true)
    }
}

/// Only applies `matchedTransitionSource` when enabled, so a day can be the
/// zoom origin in one place without clashing with another.
struct ZoomSource: ViewModifier {
    let id: DayKey
    let namespace: Namespace.ID
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct Banner: View {
    let icon: String
    let text: String
    var color: Color = Chalk.yellow
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).chalk(color)
            Text(text)
                .font(Chalk.font(13, relativeTo: .footnote))
                .chalk(Chalk.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(ChalkButtonStyle(color: color))
            }
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(SketchyRect(seed: text.stableSeed).stroke(color.opacity(0.5), style: .chalk(1.2)))
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Horizontal swipe to page between months / weeks / days, while still
/// letting vertical scrolling through.
struct PagingSwipe: ViewModifier {
    let onPage: (Int) -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 70, abs(dx) > abs(dy) * 1.6 else { return }
                    onPage(dx < 0 ? 1 : -1)
                }
        )
    }
}

extension View {
    func pagingSwipe(_ onPage: @escaping (Int) -> Void) -> some View { modifier(PagingSwipe(onPage: onPage)) }

    func pageTransition(forward: Bool) -> some View {
        transition(.asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        ))
    }
}
