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
    static let homeWidth: CGFloat = 1040     // Wispr's home: 770 column + 24 gap + 248 stats
    static let sidebarWidth: CGFloat = 216
    static let sidebarCollapsedWidth: CGFloat = 68
    static let toolbarHeight: CGFloat = 46   // window-control strip above the sheet (Flow: sheet ~46 pt down)
    static let titlebarHeight: CGFloat = 42  // traffic lights and toolbar icons centre 21 pt down, as in Flow
    static let sidebarRow: CGFloat = 36
    static let controlHeight: CGFloat = 36
    static let controlRadius: CGFloat = 10
    static let menuWidth: CGFloat = 196
    static let listRow: CGFloat = 52
    static let icon: CGFloat = 18

    // Color: warm paper and ink, each with a dark counterpart
    // Fog & sage: cool fog surfaces, charcoal text, one calm sage signal.
    static let paper = dynamic(light: 0xEEF0EE, dark: 0x121614)       // window + sidebar
    static let sheet = dynamic(light: 0xFAFBFA, dark: 0x1A1F1D)       // raised page
    static let well = dynamic(light: 0xF2F4F2, dark: 0x222826)        // inset card on the sheet
    static let selection = dynamic(light: 0xE0E7E2, dark: 0x26302B)   // selected sidebar row
    static let hover = dynamic(light: 0xE7ECE8, dark: 0x1E2522)
    static let hairline = dynamic(light: 0xDCE1DD, dark: 0x2C3430)
    static let ink = dynamic(light: 0x1E2321, dark: 0xE9EEEB)
    static let ink2 = dynamic(light: 0x626B66, dark: 0x9BA6A0)
    static let ink3 = dynamic(light: 0x5D6761, dark: 0x8B9690)
    static let inverseInk = dynamic(light: 0xFAFBFA, dark: 0x121614)
    static let signal = dynamic(light: 0x4F7F6A, dark: 0x7FB39C)      // the one accent
    static let signalSoft = dynamic(light: 0xE3ECE7, dark: 0x22322B)  // tinted fills behind signal
    static let keycap = dynamic(light: 0xDDE7E1, dark: 0x2A3A33)
    static let keycapEdge = dynamic(light: 0x9DB5A8, dark: 0x4C6A5C)
    static let listening = signal
    static let finishing = dynamic(light: 0x6F8796, dark: 0x9AB2C0)   // slate: working, not alarming
    static let success = dynamic(light: 0x3F7A5C, dark: 0x8CC4A5)
    static let danger = dynamic(light: 0xB5534A, dark: 0xE0877E)

    // Hero: a deep fog-green panel, the same in both modes, with sage and fog glows drifting in it.
    static let heroBase = dynamic(light: 0x18201C, dark: 0x0E1311)
    static let heroInk = dynamic(light: 0xF1F4F2, dark: 0xE9EEEB)
    static let heroInk2 = dynamic(light: 0xAAB8B0, dark: 0x9BA6A0)
    static let heroGlow = dynamic(light: 0x7FB39C, dark: 0x7FB39C)    // sage, lit for a dark surface
    static let heroMist = dynamic(light: 0x8FA7B4, dark: 0x7F97A4)    // fog, never used as an accent

    // Motion
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// Fast out, soft landing, for panels and the sidebar width (Wispr's most used curve).
    static let glide = Animation.timingCurve(0.05, 0.6, 0.4, 0.95, duration: 0.28)
    /// Gap between items that enter one after another (sections, rows, heatmap columns).
    static let stagger: Double = 0.05

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

/// HushKey's type scale. macOS defaults (13 pt body, 10 pt captions) read small in a
/// full-window app, so every view uses these steps instead of system text styles.
extension Font {
    static let hkTitle1 = Font.display(28)                              // page titles
    static let hkTitle2 = Font.display(22)                              // section titles, large values
    static let hkTitle3 = Font.system(size: 18, weight: .semibold)      // card titles
    static let hkHeadline = Font.system(size: 16, weight: .semibold)    // emphasised row titles
    static let hkRowTitle = Font.system(size: 16, weight: .medium)      // settings and list row labels
    static let hkBody = Font.system(size: 16)                           // reading text, list rows
    static let hkCallout = Font.system(size: 15)                        // row descriptions, secondary text
    static let hkControl = Font.system(size: 15, weight: .medium)       // buttons, menus, tabs
    static let hkCaption = Font.system(size: 13)                        // status lines
    static let hkMeta = Font.system(size: 12)                           // timestamps, counts

    /// Rounded display face for page titles, hero copy, and big numbers.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Motion

/// Content that rises 10 pt and fades in when it first appears, `order` steps after the rest.
/// Reduce Motion keeps the fade and drops the rise.
struct Reveal: ViewModifier {
    var order: Int
    var distance: CGFloat = 10
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .onAppear {
                if reduceMotion { shown = true }
                else { withAnimation(Theme.gentle.delay(Double(order) * Theme.stagger)) { shown = true } }
            }
    }
}

extension View {
    func reveal(_ order: Int = 0, distance: CGFloat = 10) -> some View {
        modifier(Reveal(order: order, distance: distance))
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

/// Sage rounded button for the one main action on a surface (Wispr: 36 pt, radius 10).
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.signal
    var foreground: Color = Theme.inverseInk
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hkControl)
            .foregroundStyle(foreground)
            .hushIconSize(16)
            .hushIconHover(hovering && isEnabled)
            .padding(.horizontal, Theme.s4)
            .frame(height: Theme.controlHeight)
            .background(tint.opacity(isEnabled ? (hovering ? 0.88 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.snappy, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Neutral filled button for secondary actions, such as a settings row's "Change".
struct SecondaryButtonStyle: ButtonStyle {
    var minWidth: CGFloat? = nil
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hkControl)
            .foregroundStyle(Theme.ink.opacity(isEnabled ? 1 : 0.4))
            .hushIconSize(16)
            .hushIconHover(hovering && isEnabled)
            .padding(.horizontal, Theme.s4)
            .frame(minWidth: minWidth)
            .frame(height: Theme.controlHeight)
            .background(hovering && isEnabled ? Theme.selection : Theme.hover,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.snappy, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Red-text neutral button for destructive actions; the confirmation dialog does the warning.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.hkControl)
            .foregroundStyle(Theme.danger.opacity(isEnabled ? 1 : 0.4))
            .hushIconSize(16)
            .hushIconHover(hovering && isEnabled)
            .padding(.horizontal, Theme.s4)
            .frame(height: Theme.controlHeight)
            .background(hovering && isEnabled ? Theme.danger.opacity(0.12) : Theme.hover,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(hovering ? Theme.ink : Theme.ink2)
            .hushIconSize(17)
            .hushIconHover(hovering)
            .frame(width: 30, height: 30)
            .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

/// A row or card that gives a little under the pointer when pressed.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

// MARK: - Keycaps

/// One key, drawn in the sage highlight used wherever HushKey shows a shortcut.
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
            ForEach(Array(Self.keys(in: label).enumerated()), id: \.offset) { _, key in
                Keycap(glyph: key, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(label)")
    }

    /// Splits "⌥⇧D" into one key per modifier glyph plus the key, keeping word keys such as
    /// "fn", "F5", "Space" and "Mouse 4" whole.
    static func keys(in label: String) -> [String] {
        if label.hasPrefix("fn") { return ["fn"] + keys(in: String(label.dropFirst(2))) }
        let modifiers = label.prefix { "⌃⌥⇧⌘".contains($0) }
        let key = label.dropFirst(modifiers.count)
        return modifiers.map(String.init) + (key.isEmpty ? [] : [String(key)])
    }
}

// MARK: - Morphing state icon

/// One stroked line that morphs between HushKey's states: a calm hush, the breath ribbon
/// opening into a lens with the voice, a working spinner, and a check. Every state uses the
/// same number of points, so SwiftUI interpolates the path itself when the state changes.
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
    @State private var speech = SpeechMeter()

    /// Speech amount eased per frame: quick to rise with a syllable, slower to fall.
    private final class SpeechMeter {
        var envelope = SpeechEnvelope()
        var target: Double = 0
        var value: Double = 0
        var lastFrame: TimeInterval?

        func advance(to time: TimeInterval) -> Double {
            let dt = min(0.05, time - (lastFrame ?? time))
            lastFrame = time
            let rate = target > value ? 18.0 : 6.0
            value += (target - value) * min(1, rate * dt)
            return value
        }
    }

    private static let morphDuration: TimeInterval = 0.45

    var body: some View {
        let isStatic = phase == .idle || phase == .done
        TimelineView(.animation(minimumInterval: 1 / 60, paused: isStatic && settled)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let raw = min(1, context.date.timeIntervalSince(changedAt) / Self.morphDuration)
            let eased = 1 - pow(1 - raw, 3)
            let spoken = phase == .listening ? speech.advance(to: time) : 0
            let target = Self.points(for: phase, time: time, speech: spoken)
            let vector = previous.map { Self.points(for: $0, time: time, speech: spoken).blended(to: target, by: eased) } ?? target
            MorphLine(vector: vector)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .onChange(of: level) { _, newValue in
            guard phase == .listening else { return }
            speech.target = Double(speech.envelope.amount(for: newValue, at: Date.timeIntervalSinceReferenceDate))
        }
        .onChange(of: phase) { old, new in
            if new != .listening { speech = SpeechMeter() }
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

    static let count = 33

    /// `speech` is 0…1 from `SpeechEnvelope`, already eased; only the listening state uses it.
    static func points(for phase: Phase, time: TimeInterval, speech: Double) -> AnimatableVector {
        var values: [Double] = []
        values.reserveCapacity(count * 2)
        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            let point: (Double, Double)
            switch phase {
            case .idle:
                // The app icon's ribbon: out along its top edge and back along its bottom, a hair
                // apart, so the stroke tapers like the icon and listening can open it into a lens.
                let u = t <= 0.5 ? 2 * t : 2 - 2 * t
                let side = t <= 0.5 ? -1.0 : 1.0
                let half = 0.035 * pow(sin(.pi * u), 1.3)
                point = (0.1 + 0.8 * u, 0.5 - 0.09 * sin(2 * .pi * u) + side * half)
            case .listening:
                // `BreathRibbon` as an outline: along the top edge, back along the bottom.
                let u = t <= 0.5 ? 2 * t : 2 - 2 * t
                let side = t <= 0.5 ? -1.0 : 1.0
                let half = 0.03 * sin(.pi * u) + 0.25 * BreathRibbon.thickness(at: u, energy: speech, mode: .live, time: time)
                point = (0.1 + 0.8 * u, 0.5 + 0.3 * BreathRibbon.spine(at: u, energy: speech, time: time) + side * half)
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

// MARK: - Small pieces

/// Small rounded chip for status and context such as the active writing mode.
struct StatusChip: View {
    var title: String
    var icon: HushIcon
    var tint: Color = Theme.ink2

    var body: some View {
        Label(title, icon: icon)
            .hushIconSize(14)
            .font(.system(size: 13, weight: .medium))
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
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.ink3)
    }
}

/// GitHub-style grid of the last few weeks; darker cells mean more dictations that day.
struct ActivityHeatmap: View {
    /// Dictations per day, keyed by the start of the day.
    var counts: [Date: Int]
    var weeks = 12
    var now = Date()

    init(entries: [DictationHistoryEntry], weeks: Int = 12, now: Date = Date()) {
        counts = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.createdAt) }.mapValues(\.count)
        self.weeks = weeks
        self.now = now
    }

    init(counts: [Date: Int], weeks: Int = 12, now: Date = Date()) {
        self.counts = counts
        self.weeks = weeks
        self.now = now
    }

    var body: some View {
        let calendar = Calendar.current
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
                                  : Theme.signal.opacity(0.3 + 0.7 * Double(count) / Double(maxCount)))
                            .frame(width: 10, height: 10)
                            .help(day > today ? "" : "\(day.formatted(date: .abbreviated, time: .omitted)): \(count) dictation\(count == 1 ? "" : "s")")
                            .accessibilityElement()
                            .accessibilityHidden(day > today)
                            .accessibilityLabel("\(day.formatted(date: .long, time: .omitted)): \(count) dictation\(count == 1 ? "" : "s")")
                    }
                }
                .reveal(column / 2, distance: 4) // the weeks fill in left to right
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation activity for the last \(weeks) weeks")
    }
}
