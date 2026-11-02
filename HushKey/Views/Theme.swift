import AppKit
import SwiftUI

// MARK: - Tokens

/// HushKey's warm editorial design system. Codes in comments match docs/DESIGN_SYSTEM.md.
enum Theme {
    // Spacing scale (S1–S7)
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48

    // Radii: R1 sheet, R2 card, R3 control; pills use Capsule
    static let r1: CGFloat = 16
    static let r2: CGFloat = 12
    static let r3: CGFloat = 8
    static let cardRadius = r2

    // Sizes: W page column, H1 sidebar row, H2 control, I1 icon
    static let pageWidth: CGFloat = 800
    static let sidebarRow: CGFloat = 34
    static let controlHeight: CGFloat = 32
    static let icon: CGFloat = 16

    // Color: warm paper and ink, each with a dark counterpart
    static let paper = dynamic(light: 0xF4F2EE, dark: 0x191816)       // window + sidebar
    static let sheet = dynamic(light: 0xFDFCFA, dark: 0x21201E)       // raised page
    static let well = dynamic(light: 0xF6F4EF, dark: 0x2A2825)        // inset card on the sheet
    static let selection = dynamic(light: 0xEAE6DF, dark: 0x2F2D2A)   // selected sidebar row
    static let hover = dynamic(light: 0xF0EDE7, dark: 0x292724)
    static let hairline = dynamic(light: 0xE6E1D8, dark: 0x35322E)
    static let ink = dynamic(light: 0x1A1918, dark: 0xF3F1EC)
    static let ink2 = dynamic(light: 0x6B665E, dark: 0xA8A298)
    static let ink3 = dynamic(light: 0x9C968C, dark: 0x77726A)
    static let inverseInk = dynamic(light: 0xFDFCFA, dark: 0x1A1918)
    static let keycap = dynamic(light: 0xF7D58E, dark: 0x5A4520)
    static let keycapEdge = dynamic(light: 0xC99A3E, dark: 0x8A6A2E)
    static let listening = Color(red: 0.90, green: 0.28, blue: 0.30)
    static let finishing = Color(red: 0.86, green: 0.58, blue: 0.20)
    static let success = Color(red: 0.25, green: 0.62, blue: 0.40)

    // Motion
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.86)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension Font {
    /// Editorial serif for page titles, hero copy, and big numbers.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Surfaces

struct CardBackground: ViewModifier {
    enum Style { case well, outlined }
    var padding: CGFloat = Theme.s4
    var style: Style = .well

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style == .well ? Theme.well : Theme.sheet,
                        in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: style == .outlined ? 1 : 0))
    }
}

extension View {
    func card(padding: CGFloat = Theme.s4, style: CardBackground.Style = .well) -> some View {
        modifier(CardBackground(padding: padding, style: style))
    }
}

// MARK: - Buttons

/// Ink capsule for the one main action on a surface.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.inverseInk)
            .padding(.horizontal, Theme.s4)
            .frame(height: Theme.controlHeight)
            .background(tint.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

/// Hairline capsule for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ink.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, Theme.s3 + 2)
            .frame(height: Theme.controlHeight)
            .background(hovering && isEnabled ? Theme.hover : Theme.sheet, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

/// Square icon-only control that shows a soft fill on hover.
struct IconButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ink2)
            .frame(width: 28, height: 28)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Keycaps

/// One key, drawn in the warm highlight used wherever HushKey shows a shortcut.
struct Keycap: View {
    var glyph: String
    var size: CGFloat = 13

    var body: some View {
        Text(glyph)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(minWidth: size * 1.85, minHeight: size * 1.85)
            .padding(.horizontal, glyph.count > 1 ? 6 : 0)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .fill(Theme.keycapEdge)
                        .offset(y: 1.5)
                    RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .fill(Theme.keycap)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                .strokeBorder(Theme.keycapEdge, lineWidth: 1))
    }
}

/// Renders a compact shortcut label such as "⌥⇧D" as a row of keycaps.
struct KeycapShortcut: View {
    var label: String
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: size * 0.28) {
            ForEach(Array(label.enumerated()), id: \.offset) { _, character in
                Keycap(glyph: String(character), size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(label)")
    }
}

// MARK: - Morphing state icon

/// One stroked line that morphs between HushKey's states: a calm hush, a live waveform,
/// a working spinner, and a check. Every state uses the same number of points, so SwiftUI
/// interpolates the path itself when the state changes.
struct MorphIcon: View {
    enum Phase: Equatable { case idle, listening, working, done }

    var phase: Phase
    var level: Float = 0
    var lineWidth: CGFloat = 2

    /// The state being morphed away from, and when the morph began. Blending is done here,
    /// frame by frame, because the live states also move every frame.
    @State private var previous: Phase?
    @State private var changedAt = Date.distantPast
    @State private var settled = true

    private static let morphDuration: TimeInterval = 0.45

    var body: some View {
        let isStatic = phase == .idle || phase == .done
        TimelineView(.animation(minimumInterval: 1 / 60, paused: isStatic && settled)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let raw = min(1, context.date.timeIntervalSince(changedAt) / Self.morphDuration)
            let eased = 1 - pow(1 - raw, 3)
            let target = Self.points(for: phase, time: time, level: level)
            let vector = previous.map { Self.points(for: $0, time: time, level: level).blended(to: target, by: eased) } ?? target
            MorphLine(vector: vector)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .onChange(of: phase) { old, _ in
            previous = old
            changedAt = Date()
            settled = false
            Task {
                try? await Task.sleep(for: .seconds(Self.morphDuration + 0.05))
                settled = true
            }
        }
        .accessibilityHidden(true)
    }

    static let count = 25

    static func points(for phase: Phase, time: TimeInterval, level: Float) -> AnimatableVector {
        var values: [Double] = []
        values.reserveCapacity(count * 2)
        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            let point: (Double, Double)
            switch phase {
            case .idle:
                point = (0.14 + 0.72 * t, 0.5 + 0.07 * sin(2 * .pi * t))
            case .listening:
                let speech = Double(min(1, max(0, (level - 0.3) / 0.5)))
                let amplitude = 0.08 + 0.26 * speech
                let envelope = sin(.pi * t)
                point = (0.1 + 0.8 * t, 0.5 + amplitude * envelope * sin(2 * .pi * (2.2 * t - time * 1.6)))
            case .working:
                let angle = -Double.pi / 2 + time * 4.2 + t * 1.65 * .pi
                point = (0.5 + 0.32 * cos(angle), 0.5 + 0.32 * sin(angle))
            case .done:
                let corner = 0.38
                point = t < corner
                    ? (0.2 + 0.2 * (t / corner), 0.52 + 0.2 * (t / corner))
                    : (0.4 + 0.42 * ((t - corner) / (1 - corner)), 0.72 - 0.44 * ((t - corner) / (1 - corner)))
            }
            values.append(point.0)
            values.append(point.1)
        }
        return AnimatableVector(values: values)
    }
}

private struct MorphLine: Shape {
    var vector: AnimatableVector

    var animatableData: AnimatableVector {
        get { vector }
        set { vector = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let values = vector.values
        guard values.count >= 4 else { return path }
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ i: Int) -> CGPoint {
            CGPoint(x: origin.x + values[i * 2] * side, y: origin.y + values[i * 2 + 1] * side)
        }
        path.move(to: point(0))
        for index in 1..<(values.count / 2) { path.addLine(to: point(index)) }
        return path
    }
}

/// Fixed-length vector so a polyline can be animated point by point.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableVector { AnimatableVector(values: []) }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, +)
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, -)
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }

    func blended(to target: AnimatableVector, by amount: Double) -> AnimatableVector {
        var delta = target - self
        delta.scale(by: amount)
        return self + delta
    }

    private static func combine(_ lhs: AnimatableVector, _ rhs: AnimatableVector,
                                _ op: (Double, Double) -> Double) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        return AnimatableVector(values: (0..<count).map { index in
            op(index < lhs.values.count ? lhs.values[index] : 0,
               index < rhs.values.count ? rhs.values[index] : 0)
        })
    }
}

// MARK: - Live waveform

/// Rolling bar waveform driven by the microphone level; flat and quiet when idle.
struct LiveWaveform: View {
    var level: Float
    var isActive: Bool
    var barCount = 24
    var tint: Color = Theme.ink

    @State private var history: [CGFloat] = []
    /// Adaptive room-noise floor on the 0…1 dB-mapped level, so bars move with speech, not hiss.
    @State private var noiseFloor: Float?

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let barWidth = max(1.5, (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let value = index < history.count ? history[index] : 0
                    Capsule()
                        .fill(tint.opacity(isActive ? 0.35 + 0.65 * value : 0.35))
                        .frame(width: barWidth, height: max(barWidth, geo.size.height * value))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.09), value: history)
        .onChange(of: level) { _, newValue in push(newValue) }
        .onChange(of: isActive) { _, active in
            if !active {
                history = []
                noiseFloor = nil
            }
        }
        .accessibilityHidden(true)
    }

    private func push(_ newValue: Float) {
        guard isActive else { return }
        // The level maps -60…0 dBFS to 0…1. Measure speech above a slowly rising noise floor
        // so a quiet room stays flat and normal speech spans roughly half to full height.
        let floor = min(newValue, (noiseFloor ?? newValue) + 0.003)
        noiseFloor = floor
        let aboveFloor = max(0, newValue - floor - 0.04) / 0.45
        let shaped = CGFloat(min(1, aboveFloor))
        var next = history
        next.append(max(0.1, shaped))
        if next.count > barCount { next.removeFirst(next.count - barCount) }
        history = next
    }
}

// MARK: - Small pieces

/// Small rounded chip for status and context such as the active writing mode.
struct StatusChip: View {
    var title: String
    var systemImage: String
    var tint: Color = Theme.ink2

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.s2 + 2)
            .frame(height: 24)
            .background(Theme.well, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// Uppercase section label used above lists and groups.
struct SectionLabel: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.ink3)
    }
}

/// GitHub-style grid of the last few weeks; darker cells mean more dictations that day.
struct ActivityHeatmap: View {
    var entries: [DictationHistoryEntry]
    var weeks = 12
    var now = Date()

    var body: some View {
        let calendar = Calendar.current
        let counts = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }.mapValues(\.count)
        let today = calendar.startOfDay(for: now)
        // Columns are weeks ending with the current one; rows are weekdays from the locale's first day.
        let weekdayOffset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let lastColumnStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today) ?? today
        let maxCount = max(1, counts.values.max() ?? 1)

        HStack(spacing: 3) {
            ForEach(0..<weeks, id: \.self) { column in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { row in
                        let start = calendar.date(byAdding: .day, value: (column - weeks + 1) * 7, to: lastColumnStart) ?? today
                        let day = calendar.date(byAdding: .day, value: row, to: start) ?? today
                        let count = counts[day] ?? 0
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(day > today ? Color.clear
                                  : count == 0 ? Theme.hairline
                                  : Theme.ink.opacity(0.3 + 0.7 * Double(count) / Double(maxCount)))
                            .frame(width: 10, height: 10)
                            .help(day > today ? "" : "\(day.formatted(date: .abbreviated, time: .omitted)): \(count) dictation\(count == 1 ? "" : "s")")
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation activity for the last \(weeks) weeks")
    }
}
