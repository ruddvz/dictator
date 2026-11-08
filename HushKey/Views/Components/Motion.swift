import SwiftUI

// HushKey's motion language. Everything here is drawn from one shape, the pill's breath ribbon
// (`BreathRibbon`), so the app moves the same way everywhere:
// - at rest a ribbon breathes once every five seconds and never travels;
// - while you speak it follows your voice; while HushKey waits or works, a bead runs along it;
// - every motion stops when the window is hidden and with Reduce Motion (the shape stays).
// Change the feel of the whole app here, not per page.

// MARK: - Tokens

enum Motion {
    /// Frame rate for ribbons that only breathe; the live pill keeps its own 120.
    static let ambientFrameRate: Double = 30
    /// Frame rate for ribbons that may follow the voice on a page (the Home band).
    static let bandFrameRate: Double = 60
    /// Seconds between voices in a chorus, so the lines never move in lockstep.
    static let chorusPhase: Double = 1.7
    /// The small header ribbon beside each page title.
    static let markSize = CGSize(width: 34, height: 8)
    /// Where Home's voice ribbon sits in its band: right of the words, on the centre line.
    static let bandFocus = UnitPoint(x: 0.76, y: 0.5)
    /// Seconds for the resting ribbon to hand over to the live one, and back.
    static let handover: Double = 0.3
    /// How brightly the band glows while HushKey opens the mic, and while it writes.
    static let bandBloomInvite: Double = 0.18
    static let bandBloomWaiting: Double = 0.25
    static let bandBloomWorking: Double = 0.4
    /// One entrance for page content: a short rise and fade.
    static let entrance = Animation.spring(response: 0.5, dampingFraction: 0.86)
}

// MARK: - Pieces

/// A small breathing ribbon: the HushKey mark in motion. Used beside page titles and in empty
/// states. It only breathes (never follows the mic), at a low frame rate.
struct RibbonMark: View {
    var size: CGSize = Motion.markSize
    var mode: BreathRibbon.Mode = .rest
    var tint: Color = Theme.signal
    @State private var visible = true

    var body: some View {
        BreathRibbon(level: 0, mode: mode, tint: tint, frameRate: Motion.ambientFrameRate, paused: !visible)
            .frame(width: size.width, height: size.height)
            .onWindowVisibilityChange { visible = $0 }
            .accessibilityHidden(true)
    }
}

/// Several ribbons stacked out of step, for several voices (Meeting notes). At rest they breathe
/// apart; when they hear speech they all follow it, so they read as a conversation.
struct ChorusRibbons: View {
    var level: Float
    var mode: BreathRibbon.Mode
    var tint: Color
    var paused: Bool
    var voices = 3

    var body: some View {
        GeometryReader { geo in
            let lane = geo.size.height / CGFloat(voices + 1)
            ZStack {
                ForEach(0..<voices, id: \.self) { k in
                    let depth = Double(k) / Double(max(1, voices - 1))
                    BreathRibbon(level: level, mode: mode,
                                 tint: tint.opacity(1 - 0.45 * depth),
                                 frameRate: Motion.bandFrameRate, paused: paused,
                                 phase: Double(k) * Motion.chorusPhase)
                        .frame(width: geo.size.width * (1 - 0.12 * depth), height: lane * 1.6)
                        .position(x: geo.size.width / 2, y: lane * CGFloat(k + 1))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The backdrop of Home's voice band: a dark sage field, faint lines gathering toward the voice,
/// and the breath ribbon resting on the right. At rest the ribbon breathes in a soft light; when
/// you speak the light rises with your voice and the ribbon opens; while HushKey works a bead
/// runs along it. `level` is the live mic level.
struct VoiceBandBackdrop: View {
    var level: Float
    var mode: BreathRibbon.Mode
    var visible: Bool
    /// The pointer is over the band: the light lifts a little, inviting you to start.
    var inviting = false

    /// How brightly the voice lights the field: the mic level while live (eased up so a whisper
    /// still shows), a steady glow while waiting or working, nothing extra at rest.
    private var bloom: Double {
        switch mode {
        case .rest: inviting ? Motion.bandBloomInvite : 0
        case .live: pow(Double(min(1, max(0, level))), 0.6)
        case .waiting: Motion.bandBloomWaiting
        case .working: Motion.bandBloomWorking
        }
    }

    var body: some View {
        GeometryReader { geo in
            let ribbon = AmbientField.ribbonRect(in: geo.size, focus: Motion.bandFocus)
            ZStack {
                AmbientField(focus: Motion.bandFocus, paused: !visible,
                             restingRibbon: mode == .rest ? Theme.heroGlow : nil, bloom: bloom)
                if mode != .rest {
                    BreathRibbon(level: level, mode: mode, tint: Theme.heroGlow,
                                 frameRate: Motion.bandFrameRate, paused: !visible, softHalo: true)
                        .frame(width: ribbon.width, height: ribbon.height)
                        .position(x: ribbon.midX, y: ribbon.midY)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: Motion.handover), value: mode == .rest)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Entrances

extension View {
    /// Cells, rows or tiles arriving in a wave: item `index` of `count` fades and rises a beat
    /// after the one before. Only on first appearance, never on data changes; still with
    /// Reduce Motion.
    func waveIn(_ index: Int, of count: Int, shown: Bool) -> some View {
        modifier(WaveIn(index: index, count: count, shown: shown))
    }
}

private struct WaveIn: ViewModifier {
    var index: Int
    var count: Int
    var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let delay = 0.6 * Double(index) / Double(max(1, count))
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .animation(reduceMotion ? nil : Motion.entrance.delay(delay), value: shown)
    }
}
