import SwiftUI

/// Shared visual language for HushKey's main surfaces: soft cards, keycap chips, and a live waveform.
enum Theme {
    static let cardRadius: CGFloat = 14
    static let listening = Color.red
    static let finishing = Color.orange
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// One physical-looking key, used to show shortcuts the way a keyboard shows them.
struct Keycap: View {
    var glyph: String
    var size: CGFloat = 13

    var body: some View {
        Text(glyph)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .frame(minWidth: size * 1.9, minHeight: size * 1.9)
            .padding(.horizontal, glyph.count > 1 ? 6 : 0)
            .foregroundStyle(.primary.opacity(0.85))
            .background {
                // Darker base offset below the face reads as a physical key edge.
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                        .fill(Color.primary.opacity(0.22))
                        .offset(y: 1.5)
                    RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
    }
}

/// Renders a compact shortcut label such as "⌥⇧D" as a row of keycaps.
struct KeycapShortcut: View {
    var label: String
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(Array(label.enumerated()), id: \.offset) { _, character in
                Keycap(glyph: String(character), size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(label)")
    }
}

/// Rolling bar waveform driven by the microphone level; flat and quiet when idle.
struct LiveWaveform: View {
    var level: Float
    var isActive: Bool
    var barCount = 24
    var tint: Color = .primary

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

/// Small rounded chip for status and context such as the active writing mode.
struct StatusChip: View {
    var title: String
    var systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// GitHub-style grid of the last few weeks; darker cells mean more dictations that day.
struct ActivityHeatmap: View {
    var entries: [DictationHistoryEntry]
    var weeks = 10
    var now = Date()

    var body: some View {
        let calendar = Calendar.current
        let counts = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }.mapValues(\.count)
        let today = calendar.startOfDay(for: now)
        // Columns are weeks ending with the current one; rows are weekdays from the locale's first day.
        let weekdayOffset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let lastColumnStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today) ?? today
        let maxCount = max(1, counts.values.max() ?? 1)

        VStack(alignment: .leading, spacing: 6) {
            Text("Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(0..<weeks, id: \.self) { column in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { row in
                            let start = calendar.date(byAdding: .day, value: (column - weeks + 1) * 7, to: lastColumnStart) ?? today
                            let day = calendar.date(byAdding: .day, value: row, to: start) ?? today
                            let count = counts[day] ?? 0
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(day > today ? Color.clear
                                      : count == 0 ? Color.primary.opacity(0.07)
                                      : Color.accentColor.opacity(0.3 + 0.7 * Double(count) / Double(maxCount)))
                                .frame(width: 11, height: 11)
                                .help(day > today ? "" : "\(day.formatted(date: .abbreviated, time: .omitted)): \(count) dictation\(count == 1 ? "" : "s")")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictation activity for the last \(weeks) weeks")
    }
}
