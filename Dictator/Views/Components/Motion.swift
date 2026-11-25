import SwiftUI

// Dictator's motion language. Everything here is drawn from one shape, the pill's breath ribbon
// (`BreathRibbon`), so the app moves the same way everywhere:
// - at rest a ribbon breathes once every five seconds and never travels;
// - while you speak it follows your voice; while Dictator waits or works, a bead runs along it;
// - every motion stops when the window is hidden and with Reduce Motion (the shape stays).
// Change the feel of the whole app here, not per page.

// MARK: - Tokens

enum Motion {
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
    /// How brightly the band glows while Dictator opens the mic, and while it writes.
    static let bandBloomInvite: Double = 0.18
    static let bandBloomWaiting: Double = 0.25
    static let bandBloomWorking: Double = 0.4
    /// One entrance for page content: a short rise and fade.
    static var entrance: Animation { Theme.gentle }
    /// The page mark's one breath when a page opens: in, then out. Seconds.
    static let markBreathIn: Double = 0.38
    static let markBreathOut: Double = 0.7
    /// How far the page mark swells on that breath (speech energy, 0…1).
    static let markSwell: Double = 0.5
    /// How long outgoing content (a page, a settings section) takes to fade, so old and new never
    /// overlap for long. Seconds.
    static let exit: Double = 0.1
    /// How long a confirmation ("Copied", a check) stays before it settles back. Seconds.
    static let confirmHold: Double = 1.4
}

// MARK: - Nudge

/// A short sideways nudge, for a notice that needs a second look (the pill's error card).
/// Runs once when the view appears and again each time `trigger` changes; about a third of a
/// second; still with Reduce Motion.
struct Nudge<Trigger: Equatable>: ViewModifier {
    var trigger: Trigger
    @State private var count = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .onAppear { count += 1 }
                .onChange(of: trigger) { count += 1 }
                .keyframeAnimator(initialValue: 0.0, trigger: count) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-5, duration: 0.07)
                    CubicKeyframe(4, duration: 0.08)
                    CubicKeyframe(-2, duration: 0.08)
                    SpringKeyframe(0, duration: 0.14, spring: .snappy)
                }
            }
        }
    }
}

extension View {
    func nudge<Trigger: Equatable>(on trigger: Trigger) -> some View {
        modifier(Nudge(trigger: trigger))
    }
}

// MARK: - Pieces

/// The small Dictator mark beside each page title. It takes one breath when the page opens
/// (swells and settles in about a second) and then holds still. It used to breathe for as long
/// as the page was open, a 30 fps `TimelineView` + `Canvas` inside every page's scroll view,
/// which re-rendered the page header continuously and cost CPU while scrolling or idle.
/// Reduce Motion: drawn still.
struct RibbonMark: View {
    var size: CGSize = Motion.markSize
    var tint: Color = Theme.signal
    @State private var swell: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RibbonMarkShape(swell: swell)
            .fill(LinearGradient(colors: [tint.opacity(0.45), tint, tint.opacity(0.45)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: size.width, height: size.height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: Motion.markBreathIn)) {
                    swell = Motion.markSwell
                } completion: {
                    withAnimation(.easeInOut(duration: Motion.markBreathOut)) { swell = 0 }
                }
            }
            .accessibilityHidden(true)
    }
}

/// The breath ribbon's outline at a fixed moment, with its swell animatable, so a one-off
/// breath is interpolated by SwiftUI without a per-frame clock.
struct RibbonMarkShape: Shape {
    var swell: Double
    /// A fixed point in the resting breath, a little past its fullest, so the still mark reads.
    static let restTime: TimeInterval = BreathRibbon.restLoop * 0.3

    var animatableData: Double {
        get { swell }
        set { swell = newValue }
    }

    func path(in rect: CGRect) -> Path {
        BreathRibbon.path(in: rect.size, energy: swell, mode: .live, time: Self.restTime)
            .offsetBy(dx: rect.minX, dy: rect.minY)
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
/// you speak the light rises with your voice and the ribbon opens; while Dictator works a bead
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
