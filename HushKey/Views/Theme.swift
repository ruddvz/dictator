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
            .background(
                RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 1.5))
            .overlay(RoundedRectangle(cornerRadius: size * 0.45, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5))
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

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let barWidth = max(1.5, (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let value = index < history.count ? history[index] : 0
                    Capsule()
                        .fill(tint.opacity(isActive ? 0.9 : 0.35))
                        .frame(width: barWidth, height: max(barWidth, geo.size.height * value))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.09), value: history)
        .onChange(of: level) { _, newValue in push(newValue) }
        .onChange(of: isActive) { _, active in if !active { history = [] } }
        .accessibilityHidden(true)
    }

    private func push(_ newValue: Float) {
        guard isActive else { return }
        // Shape the level so normal speech fills the bar without clipping.
        let shaped = CGFloat(min(1, pow(Double(max(newValue, 0)), 0.6) * 1.4))
        var next = history
        next.append(max(0.08, shaped))
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
