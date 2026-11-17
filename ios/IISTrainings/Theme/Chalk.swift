import SwiftUI

/// The chalkboard look: slate-green board, chalk-white type, pastel chalk
/// colors and hand-drawn strokes.
enum Chalk {
    static let board = Color(red: 0.17, green: 0.26, blue: 0.22)
    static let boardDeep = Color(red: 0.09, green: 0.15, blue: 0.12)
    static let boardLight = Color(red: 0.24, green: 0.34, blue: 0.29)

    static let white = Color(red: 0.96, green: 0.95, blue: 0.90)
    static let dim = white.opacity(0.62)
    static let faint = white.opacity(0.16)
    static let line = white.opacity(0.11)

    static let yellow = Color(red: 0.99, green: 0.90, blue: 0.55)
    static let pink = Color(red: 0.98, green: 0.66, blue: 0.74)
    static let blue = Color(red: 0.62, green: 0.82, blue: 0.98)
    static let green = Color(red: 0.72, green: 0.93, blue: 0.68)
    static let orange = Color(red: 1.00, green: 0.74, blue: 0.52)
    static let lavender = Color(red: 0.80, green: 0.74, blue: 0.98)

    static let palette: [Color] = [yellow, pink, blue, green, orange, lavender]

    /// Chalkboard SE ships with iOS and reads like neat chalk handwriting.
    static func font(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? "ChalkboardSE-Bold" : "ChalkboardSE-Regular", size: size, relativeTo: style)
    }

    /// Chalkduster: the dusty, smeared display face for big headings.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("Chalkduster", size: size, relativeTo: style)
    }

    /// Turns a monday label color into a soft chalk pastel that stays
    /// readable on the dark board.
    static func tint(_ hex: String?, fallbackSeed: String = "") -> Color {
        if let c = Color(hex: hex) {
            return c.mix(with: white, by: 0.38)
        }
        let i = Int(fallbackSeed.stableSeed % UInt64(palette.count))
        return palette[i]
    }

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
}

extension Color {
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

// MARK: - Chalk text

struct ChalkTextStyle: ViewModifier {
    var color: Color = Chalk.white
    func body(content: Content) -> some View {
        content
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.45), radius: 0.8)
    }
}

extension View {
    func chalk(_ color: Color = Chalk.white) -> some View { modifier(ChalkTextStyle(color: color)) }
}

// MARK: - Seeded randomness

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    /// 0...1
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }

    /// -1...1
    mutating func signed() -> CGFloat { next() * 2 - 1 }
}

// MARK: - Hand-drawn shapes

/// A rectangle drawn by hand with chalk: slightly bowed sides and corners
/// that overshoot, like a teacher boxing something on the board.
struct SketchyRect: Shape {
    var seed: UInt64 = 7
    var wobble: CGFloat = 1.6
    var overshoot: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        let r = rect.insetBy(dx: 1, dy: 1)
        let corners = [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
        ]
        var p = Path()
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 1)
            let ux = dx / len, uy = dy / len
            let o = min(overshoot, len * 0.08)
            let start = CGPoint(x: a.x - ux * o * rng.next() + rng.signed() * wobble * 0.5,
                                y: a.y - uy * o * rng.next() + rng.signed() * wobble * 0.5)
            let end = CGPoint(x: b.x + ux * o * rng.next() + rng.signed() * wobble * 0.5,
                              y: b.y + uy * o * rng.next() + rng.signed() * wobble * 0.5)
            let bow = rng.signed() * wobble * min(1, len / 60)
            let mid = CGPoint(x: (a.x + b.x) / 2 - uy * bow, y: (a.y + b.y) / 2 + ux * bow)
            p.move(to: start)
            p.addQuadCurve(to: end, control: mid)
        }
        return p
    }
}

/// A hand-drawn loop, used to circle today's date.
struct ChalkCircle: Shape {
    var seed: UInt64 = 3
    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2, ry = rect.height / 2
        var p = Path()
        let steps = 48
        let turns: CGFloat = 1.12
        let startAngle = -CGFloat.pi * 0.65
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let ang = startAngle + t * turns * 2 * .pi
            let drift = 1 + 0.06 * sin(t * .pi * 3) + 0.03 * rng.signed() + 0.05 * t
            let pt = CGPoint(x: c.x + cos(ang) * rx * drift, y: c.y + sin(ang) * ry * drift)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// A wobbly underline.
struct ChalkUnderline: Shape {
    var seed: UInt64 = 11
    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rng.signed() * 1.5))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY + rng.signed() * 2),
            control1: CGPoint(x: rect.width * 0.33, y: rect.midY - 3 + rng.signed() * 2),
            control2: CGPoint(x: rect.width * 0.66, y: rect.midY + 3 + rng.signed() * 2)
        )
        return p
    }
}

extension StrokeStyle {
    static func chalk(_ width: CGFloat = 1.6) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

// MARK: - The board

/// Slate with smudges and chalk dust. Drawn once per size.
struct ChalkboardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Chalk.board, Chalk.boardDeep], startPoint: .top, endPoint: .bottom)
            Canvas(rendersAsynchronously: true) { ctx, size in
                var rng = SeededRandom(seed: 2026)

                // Eraser smudges: wide, nearly invisible arcs.
                for _ in 0..<16 {
                    var p = Path()
                    let y = rng.next() * size.height
                    let x = rng.next() * size.width * 0.6
                    p.move(to: CGPoint(x: x, y: y))
                    p.addQuadCurve(
                        to: CGPoint(x: x + 120 + rng.next() * 260, y: y + rng.signed() * 40),
                        control: CGPoint(x: x + 90, y: y + rng.signed() * 70)
                    )
                    ctx.stroke(p, with: .color(.white.opacity(0.018 + rng.next() * 0.02)),
                               style: StrokeStyle(lineWidth: 26 + rng.next() * 30, lineCap: .round))
                }

                // Dust specks.
                let count = min(3500, Int(size.width * size.height / 260))
                for _ in 0..<count {
                    let d = 0.4 + rng.next() * 1.3
                    let rect = CGRect(x: rng.next() * size.width, y: rng.next() * size.height, width: d, height: d)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.03 + rng.next() * 0.09)))
                }
            }
            RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 200, endRadius: 900)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Small rounded chalk tag, e.g. a status.
struct ChalkPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(Chalk.font(12, bold: true, relativeTo: .caption))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .chalk(color)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.55), lineWidth: 1))
    }
}

/// Classic five-bar tally marks, drawn in chalk, for "how many classes".
struct TallyMarks: View {
    let count: Int
    var color: Color = Chalk.dim
    var height: CGFloat = 10

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: UInt64(count) &* 97)
            let gap: CGFloat = 3
            var x: CGFloat = 1
            var drawn = 0
            while drawn < count, x < size.width {
                let inGroup = min(5, count - drawn)
                let groupStart = x
                for i in 0..<min(4, inGroup) {
                    var p = Path()
                    let xx = x + CGFloat(i) * gap
                    p.move(to: CGPoint(x: xx + rng.signed() * 0.4, y: 0.5))
                    p.addLine(to: CGPoint(x: xx + rng.signed() * 0.6, y: size.height - 0.5))
                    ctx.stroke(p, with: .color(color), style: .chalk(1.1))
                }
                if inGroup == 5 {
                    var p = Path()
                    p.move(to: CGPoint(x: groupStart - 1.5, y: size.height * 0.8))
                    p.addLine(to: CGPoint(x: groupStart + 3 * gap + 1.5, y: size.height * 0.2))
                    ctx.stroke(p, with: .color(color), style: .chalk(1.1))
                }
                x += CGFloat(min(4, inGroup)) * gap + 4
                drawn += inGroup
            }
        }
        .frame(width: CGFloat((count + 4) / 5) * (4 * 3 + 4) + 2, height: height)
        .accessibilityLabel("\(count) classes")
    }
}
