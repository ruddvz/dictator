import AppKit
import SwiftUI

// MARK: - Breath ribbon

/// Dictator's voice form: one ribbon that rests as a thin breathing line and swells with speech.
/// Not bouncing bars: Dictator also hears whispered and mouthed speech, so the form has to show
/// "heard" clearly at whisper level. Thickness follows √-ish speech, so a whisper already opens
/// the line. Used in the floating pill and the home hero.
struct BreathRibbon: View {
    enum Mode: Equatable { case rest, live, waiting, working }

    var level: Float = 0
    var mode: Mode
    var tint: Color = Theme.signal
    /// Upper frame rate. The pill runs at 120 to follow syllables smoothly on ProMotion displays; ambient uses run slower.
    var frameRate: Double = 120
    /// Stops the clock, for example while the window is hidden.
    var paused = false
    /// Seconds added to the clock, so ribbons drawn together breathe out of step (Chorus).
    var phase: Double = 0
    /// A feathered halo in graded steps instead of one flat band, for large ribbons on a page.
    var softHalo = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-frame smoothing state; a class so the Canvas can update it without re-rendering.
    private final class Smoother {
        var envelope = SpeechEnvelope()
        var target: Double = 0
        var value: Double = 0
        var lastFrame: TimeInterval?
    }
    @State private var smoother = Smoother()

    /// One resting breath, in seconds; the resting ribbon repeats exactly after it.
    static let restLoop: TimeInterval = 5

    /// Half-thickness of the resting line, as a fraction of half the view's height.
    static let restThickness = 0.14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / frameRate, paused: paused || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                let energy = mode == .live ? advance(to: time) : 0
                // Reduce Motion: nothing travels or pulses; the live voice level still shapes the line.
                let flow = reduceMotion ? phase : time + phase
                let fade = reduceMotion ? 0.78 : 1
                Self.draw(in: graphics, size: size, energy: energy, mode: mode, time: flow, tint: tint,
                          opacity: fade, softHalo: softHalo)
            }
        }
        .onChange(of: level) { _, newValue in
            guard mode == .live else { return }
            smoother.target = Double(smoother.envelope.amount(for: newValue, at: Date.timeIntervalSinceReferenceDate))
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .rest {
                smoother.target = 0
            }
        }
        // Already live when it appears (Home opened mid-dictation): start from the current level.
        .onAppear {
            guard mode == .live else { return }
            smoother.target = Double(smoother.envelope.amount(for: level, at: Date.timeIntervalSinceReferenceDate))
        }
        .accessibilityHidden(true)
    }

    /// Eases toward the latest level: quick to rise with a syllable, slower to fall.
    private func advance(to time: TimeInterval) -> Double {
        let dt = min(0.05, time - (smoother.lastFrame ?? time))
        smoother.lastFrame = time
        let rate = smoother.target > smoother.value ? 20.0 : 8.0
        smoother.value += (smoother.target - smoother.value) * min(1, rate * dt)
        return smoother.value
    }

    // MARK: Shape

    /// Half-thickness at `x` (0…1 along the ribbon) as a fraction of half the height, 0…1.
    /// `energy` is 0…1 from `SpeechEnvelope`, already eased.
    static func thickness(at x: Double, energy: Double, mode: Mode, time: TimeInterval) -> Double {
        let taper = pow(max(0, sin(.pi * x)), 0.9)
        // One slow breath every 5 s, with a faint ripple along the line.
        let breath = 0.5 + 0.5 * sin(time * 2 * .pi / restLoop)
        let ripple = 0.5 + 0.5 * sin(x * 7 - time * 2 * .pi / restLoop)
        let resting = taper * restThickness * (0.55 + 0.45 * breath) * (0.85 + 0.3 * ripple)
        switch mode {
        case .rest:
            return resting
        case .live:
            // Whisper boost: a quarter of full speech already opens the ribbon past halfway.
            let spoken = pow(min(1, max(0, energy)), 0.45)
            var lobes = 0.0
            for k in 0..<3 {
                let kd = Double(k)
                let centre = 0.5 + 0.26 * sin(time * (0.9 + 0.37 * kd) + kd * 2.1)
                let width = 0.15 + 0.05 * kd
                let pulse = 0.72 + 0.28 * sin(time * (5.3 + 1.9 * kd) + kd)
                let distance = (x - centre) / width
                lobes += (1 - 0.25 * kd) * pulse * exp(-distance * distance)
            }
            return min(1, resting + (1 - restThickness) * spoken * min(1, 0.85 * lobes) * taper)
        case .waiting, .working:
            // A bead of breath travels along the line: slower while waiting, brisker while working.
            let speed = mode == .waiting ? 0.35 : 0.8
            let position = (time * speed).truncatingRemainder(dividingBy: 1) * 1.4 - 0.2
            let distance = (x - position) / 0.12
            return resting + (mode == .waiting ? 0.25 : 0.45) * exp(-distance * distance) * taper
        }
    }

    /// Vertical drift of the ribbon's centre at `x`, as a fraction of half the height.
    static func spine(at x: Double, energy: Double, time: TimeInterval) -> Double {
        let taper = sin(.pi * max(0, min(1, x)))
        return (0.02 + 0.1 * pow(min(1, max(0, energy)), 0.6)) * sin(2 * .pi * (1.1 * x - 0.4 * time)) * taper
    }

    /// Thickness at `count` evenly spaced points; for tests and anything that samples the form.
    static func profile(count: Int, energy: Double, mode: Mode, time: TimeInterval) -> [Double] {
        (0..<count).map { thickness(at: Double($0) / Double(max(1, count - 1)), energy: energy, mode: mode, time: time) }
    }

    static func draw(in graphics: GraphicsContext, size: CGSize, energy: Double, mode: Mode,
                     time: TimeInterval, tint: Color, opacity: Double = 1, softHalo: Bool = false) {
        let tint = tint.flattened(in: graphics.environment)
        let midY = size.height / 2
        let fill = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [tint.opacity(0.45 * opacity), tint.opacity(opacity), tint.opacity(0.45 * opacity)]),
            startPoint: CGPoint(x: 0, y: midY), endPoint: CGPoint(x: size.width, y: midY))
        if softHalo, mode != .rest {
            // Widening veils that follow the ribbon's own shape, each faint: together they feather
            // the edge into the field instead of drawing a second, harder band.
            let veil = 0.035 + 0.06 * energy
            for pad in [0.42, 0.3, 0.2, 0.12, 0.06] {
                graphics.fill(path(in: size, energy: energy, mode: mode, time: time, pad: pad),
                              with: .color(tint.opacity(veil * opacity)))
            }
        } else if mode == .live || mode == .working {
            // A soft halo around the ribbon, brighter with the voice, so quiet speech still glows.
            let halo = 0.1 + 0.2 * energy
            graphics.fill(path(in: size, energy: energy, mode: mode, time: time, spread: 1.8),
                          with: .color(tint.opacity(halo * opacity)))
        }
        graphics.fill(path(in: size, energy: energy, mode: mode, time: time), with: fill)
    }

    /// The ribbon's outline: along the top edge, back along the bottom, smoothed between samples.
    /// `spread` scales the thickness (the pill's halo); `pad` adds a margin, as a fraction of half
    /// the height, that keeps the ribbon's shape (the page ribbons' feathered veils).
    static func path(in size: CGSize, energy: Double, mode: Mode, time: TimeInterval,
                     spread: Double = 1, pad: Double = 0) -> Path {
        let samples = max(16, Int(size.width / 3))
        let half = size.height / 2
        var top: [CGPoint] = [], bottom: [CGPoint] = []
        top.reserveCapacity(samples + 1)
        bottom.reserveCapacity(samples + 1)
        for index in 0...samples {
            let x = Double(index) / Double(samples)
            let centre = half + CGFloat(spine(at: x, energy: energy, time: time)) * half
            let taper = CGFloat(sqrt(max(0, sin(.pi * x))))
            let body = CGFloat(min(1, thickness(at: x, energy: energy, mode: mode, time: time) * spread)) * half * 0.86
            let margin = CGFloat(pad) * half * CGFloat(sin(.pi * x))
            let edge = min(half, max(0.75 * taper, body + margin))
            let px = CGFloat(x) * size.width
            top.append(CGPoint(x: px, y: centre - edge))
            bottom.append(CGPoint(x: px, y: centre + edge))
        }
        var path = Path()
        addSmooth(top, to: &path, startsPath: true)
        addSmooth(bottom.reversed(), to: &path, startsPath: false)
        path.closeSubpath()
        return path
    }

    /// Quadratic segments through the midpoints of `points`, so samples join without corners.
    static func addSmooth(_ points: [CGPoint], to path: inout Path, startsPath: Bool) {
        guard let first = points.first, points.count > 2 else { return }
        if startsPath { path.move(to: first) } else { path.addLine(to: first) }
        for index in 1..<(points.count - 1) {
            let next = points[index + 1]
            let mid = CGPoint(x: (points[index].x + next.x) / 2, y: (points[index].y + next.y) / 2)
            path.addQuadCurve(to: mid, control: points[index])
        }
        path.addLine(to: points[points.count - 1])
    }
}

// MARK: - Ambient field

/// Slow generative backdrop for the home hero: soft sage and fog glows drifting like breath on
/// glass, faint ribbons that gather toward `focus`, and, at rest, the breath ribbon itself.
/// Built from Core Animation layers whose shapes and positions are precomputed keyframe loops,
/// so the render server animates them and the app does no per-frame work. (Redrawing a SwiftUI
/// `Canvas` each frame re-lays out the whole window: about a fifth of a core.) Paused while
/// `paused` (window hidden); a still frame with Reduce Motion.
struct AmbientField: NSViewRepresentable {
    var focus = UnitPoint(x: 0.78, y: 0.5)
    var paused = false
    /// Draws the resting `BreathRibbon` at the focus in this colour. Nil while a live ribbon is
    /// shown on top instead; the resting one then fades out under it.
    var restingRibbon: Color?
    /// 0…1: how brightly the voice lights the field around the ribbon (the mic level while you
    /// speak, a steady glow while Dictator works, 0 at rest, where it only breathes).
    var bloom: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> AmbientFieldView { AmbientFieldView() }

    func updateNSView(_ view: AmbientFieldView, context: Context) {
        view.configure(focus: focus, ribbon: restingRibbon.map { NSColor($0) }, bloom: bloom,
                       animated: !reduceMotion, paused: paused)
    }

    /// Where the voice ribbon sits: 30 % of the width, centred on the focus.
    static func ribbonRect(in size: CGSize, focus: UnitPoint) -> CGRect {
        let width = size.width * 0.3, height = min(96, size.height * 0.5)
        return CGRect(x: size.width * focus.x - width / 2, y: size.height * focus.y - height / 2,
                      width: width, height: height)
    }

    /// Seconds before the ribbons' shapes repeat; every drift is a whole number of turns in it.
    static let ribbonLoop: TimeInterval = 40
    /// A composed moment to show when nothing may move.
    static let stillTime: TimeInterval = 13

    /// Glows: each drifts on its own slow loop, 40–70 s around, as fractions of the size.
    struct Glow {
        var mist: Bool, opacity: Float, periodX: Double, periodY: Double, phase: Double, radius: CGFloat
    }
    static let glows = [
        Glow(mist: false, opacity: 0.34, periodX: 47, periodY: 61, phase: 0.0, radius: 0.55),
        Glow(mist: true, opacity: 0.22, periodX: 67, periodY: 41, phase: 2.3, radius: 0.6),
        Glow(mist: false, opacity: 0.16, periodX: 53, periodY: 71, phase: 4.1, radius: 0.42),
    ]

    static func glowCentre(_ glow: Glow, in size: CGSize, time: TimeInterval) -> CGPoint {
        CGPoint(x: size.width * (0.55 + 0.4 * sin(time * 2 * .pi / glow.periodX + glow.phase)),
                y: size.height * (0.5 + 0.55 * sin(time * 2 * .pi / glow.periodY + glow.phase * 1.7)))
    }

    static let lineCount = 7

    /// The light the voice casts: an ellipse this many ribbon-sizes across, centred on the ribbon.
    static let bloomSpread = CGSize(width: 2.2, height: 3.4)
    /// Bloom opacity at rest (it breathes with the ribbon) and the extra a full voice adds.
    static let bloomRest: Float = 0.24, bloomVoice: Float = 0.6
    /// The faint lines fade to this behind the words on the left, so the type sits on calm ground.
    static let linesUnderWords: Float = 0.3
    /// How much lighter the top of the field is: a sheen, as if lit from above.
    static let sheen: CGFloat = 0.06

    /// One of the seven faint ribbons that pinch toward the focus, like sound gathering at the voice.
    static func line(_ line: Int, in size: CGSize, focus: UnitPoint, time: TimeInterval) -> CGPath {
        let k = Double(line)
        let offset = lineOffset(line)
        let turn = time / ribbonLoop
        let swellAt = ((turn + k * 0.37).truncatingRemainder(dividingBy: 1)) * 1.4 - 0.2
        let focusX = Double(focus.x), focusY = size.height * focus.y
        let samples = max(24, Int(size.width / 8))
        var top: [CGPoint] = [], bottom: [CGPoint] = []
        for index in 0...samples {
            let x = Double(index) / Double(samples)
            let reach = (x - focusX) / (0.45 * max(focusX, 1 - focusX))
            let spread = 0.18 + 0.82 * (1 - exp(-reach * reach)) // a soft waist, not a corner
            let wave = sin(2 * .pi * (0.9 * x + k * 0.13 - turn * Double(1 + line % 2)))
            let y = focusY + CGFloat((offset * 0.46 + 0.07 * wave) * spread) * size.height
            let distance = (x - swellAt) / 0.1
            let half = CGFloat(0.35 + 1.4 * exp(-distance * distance))
            top.append(CGPoint(x: CGFloat(x) * size.width, y: y - half))
            bottom.append(CGPoint(x: CGFloat(x) * size.width, y: y + half))
        }
        var path = Path()
        BreathRibbon.addSmooth(top, to: &path, startsPath: true)
        BreathRibbon.addSmooth(bottom.reversed(), to: &path, startsPath: false)
        path.closeSubpath()
        return path.cgPath
    }

    /// −1…1 from the top line to the bottom one.
    static func lineOffset(_ line: Int) -> Double {
        let middle = Double(lineCount - 1) / 2
        return (Double(line) - middle) / middle
    }
}

final class AmbientFieldView: NSView {
    private let glowLayers = AmbientField.glows.map { _ in CAGradientLayer() }
    private let lineLayers = (0..<AmbientField.lineCount).map { _ in CAShapeLayer() }
    private let ribbonLayer = CAGradientLayer()
    private let ribbonMask = CAShapeLayer()
    private let linesHost = CALayer()
    private let linesMask = CAGradientLayer()
    private let bloomHost = CALayer()
    private let bloomLayer = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()
    /// Our own top-down root, so shapes use SwiftUI's coordinates and pausing leaves AppKit's layer alone.
    private let root = CALayer()

    private var focus = UnitPoint(x: 0.78, y: 0.5)
    private var ribbonColor: NSColor?
    private var ribbonShown = false
    private var bloom: Double = -1
    private var animated = true
    /// Paused by the owner (window hidden), and separately while the user scrolls. The two are
    /// kept apart so one can't undo the other.
    private var ownerPaused = false
    private var scrollPaused = false
    private var paused = false
    private var scrollMonitor: Any?
    private var scrollResume: DispatchWorkItem?
    private var builtSize: CGSize = .zero
    private var builtAnimated: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        root.isGeometryFlipped = true
        layer?.addSublayer(root)
        for glow in glowLayers {
            glow.type = .radial
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            root.addSublayer(glow)
        }
        // Lines sit in a host masked lighter on the left, behind the words.
        linesMask.startPoint = CGPoint(x: 0, y: 0.5)
        linesMask.endPoint = CGPoint(x: 1, y: 0.5)
        let under = NSColor.black.withAlphaComponent(CGFloat(AmbientField.linesUnderWords)).cgColor
        linesMask.colors = [under, under, NSColor.black.cgColor]
        linesMask.locations = [0, 0.3, 0.6]
        linesHost.mask = linesMask
        lineLayers.forEach { linesHost.addSublayer($0) }
        root.addSublayer(linesHost)
        bloomLayer.type = .radial
        bloomLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloomLayer.endPoint = CGPoint(x: 1, y: 1)
        bloomHost.addSublayer(bloomLayer)
        root.addSublayer(bloomHost)
        sheenLayer.startPoint = CGPoint(x: 0.5, y: 0)
        sheenLayer.endPoint = CGPoint(x: 0.5, y: 0.5)
        root.addSublayer(sheenLayer)
        ribbonLayer.startPoint = CGPoint(x: 0, y: 0.5)
        ribbonLayer.endPoint = CGPoint(x: 1, y: 0.5)
        ribbonLayer.mask = ribbonMask
        ribbonLayer.opacity = 0
        root.addSublayer(ribbonLayer)
    }

    required init?(coder: NSCoder) { nil }

    func configure(focus: UnitPoint, ribbon: NSColor?, bloom: Double, animated: Bool, paused: Bool) {
        let rebuild = focus != self.focus || animated != builtAnimated
        self.focus = focus
        self.animated = animated
        if let ribbon, ribbon != ribbonColor {
            ribbonColor = ribbon
            applyColors()
        }
        setRibbonShown(ribbon != nil)
        setBloom(bloom)
        if rebuild { builtSize = .zero; needsLayout = true }
        ownerPaused = paused
        updatePause()
    }

    /// The resting ribbon hands over to the live one (and back) with a short crossfade, not a cut.
    private func setRibbonShown(_ shown: Bool) {
        guard shown != ribbonShown else { return }
        ribbonShown = shown
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? Motion.handover : 0)
        ribbonLayer.opacity = shown ? 1 : 0
        CATransaction.commit()
    }

    /// Eased toward the voice: quick enough to follow syllables, never a flicker.
    private func setBloom(_ value: Double) {
        let value = min(1, max(0, value))
        guard abs(value - bloom) > 0.01 else { return }
        bloom = value
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.18 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        bloomHost.opacity = AmbientField.bloomRest + AmbientField.bloomVoice * Float(value)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        guard bounds.width > 1, bounds.height > 1 else { return }
        if abs(bounds.width - builtSize.width) > 0.5 || abs(bounds.height - builtSize.height) > 0.5 {
            build(size: bounds.size)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// Theme colours are dynamic; resolve them for this view's light or dark appearance.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            root.backgroundColor = NSColor(Theme.heroBase).cgColor
            for (glow, spec) in zip(glowLayers, AmbientField.glows) {
                let color = NSColor(spec.mist ? Theme.heroMist : Theme.heroGlow)
                glow.colors = [color.withAlphaComponent(CGFloat(spec.opacity)).cgColor, color.withAlphaComponent(0).cgColor]
            }
            let ink = NSColor(Theme.heroInk)
            for (index, line) in lineLayers.enumerated() {
                line.fillColor = ink.withAlphaComponent(0.05 + 0.07 * (1 - abs(AmbientField.lineOffset(index)))).cgColor
            }
            if let ribbonColor {
                ribbonLayer.colors = [ribbonColor.withAlphaComponent(0.45).cgColor, ribbonColor.cgColor,
                                      ribbonColor.withAlphaComponent(0.45).cgColor]
            }
            let glow = NSColor(Theme.heroGlow)
            bloomLayer.colors = [glow.cgColor, glow.withAlphaComponent(0.35).cgColor, glow.withAlphaComponent(0).cgColor]
            bloomLayer.locations = [0, 0.35, 1]
            let lit = NSColor(Theme.heroInk)
            sheenLayer.colors = [lit.withAlphaComponent(AmbientField.sheen).cgColor, lit.withAlphaComponent(0).cgColor]
        }
    }

    /// Lays out every layer at its still frame and, unless motion is off, adds looping keyframes.
    private func build(size: CGSize) {
        builtSize = size
        builtAnimated = animated
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        root.frame = CGRect(origin: .zero, size: size)
        applyColors()
        linesHost.frame = root.bounds
        linesMask.frame = root.bounds
        sheenLayer.frame = root.bounds
        bloomHost.frame = root.bounds
        let still = AmbientField.stillTime

        for (glow, spec) in zip(glowLayers, AmbientField.glows) {
            glow.removeAllAnimations()
            let radius = size.width * spec.radius
            glow.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            glow.position = AmbientField.glowCentre(spec, in: size, time: still)
            if animated {
                let period = spec.periodX * spec.periodY / gcd(spec.periodX, spec.periodY)
                glow.add(loop(keyPath: "position", duration: period, frames: 240) {
                    NSValue(point: AmbientField.glowCentre(spec, in: size, time: $0))
                }, forKey: "drift")
            }
        }

        for (index, line) in lineLayers.enumerated() {
            line.removeAllAnimations()
            line.frame = CGRect(origin: .zero, size: size)
            line.path = AmbientField.line(index, in: size, focus: focus, time: still)
            if animated {
                line.add(loop(keyPath: "path", duration: AmbientField.ribbonLoop, frames: 64) {
                    AmbientField.line(index, in: size, focus: self.focus, time: $0)
                }, forKey: "flow")
            }
        }

        let rect = AmbientField.ribbonRect(in: size, focus: focus)
        // The bloom breathes with the resting ribbon; the voice raises the host's opacity on top.
        let spread = AmbientField.bloomSpread
        bloomLayer.bounds = CGRect(x: 0, y: 0, width: rect.width * spread.width, height: rect.height * spread.height)
        bloomLayer.position = CGPoint(x: rect.midX, y: rect.midY)
        bloomLayer.removeAllAnimations()
        bloomLayer.opacity = 0.85
        if animated {
            bloomLayer.add(loop(keyPath: "opacity", duration: BreathRibbon.restLoop, frames: 40) {
                NSNumber(value: 0.7 + 0.3 * (0.5 + 0.5 * sin($0 * 2 * .pi / BreathRibbon.restLoop)))
            }, forKey: "breath")
        }
        ribbonLayer.frame = rect
        ribbonMask.frame = CGRect(origin: .zero, size: rect.size)
        ribbonMask.removeAllAnimations()
        ribbonMask.path = BreathRibbon.path(in: rect.size, energy: 0, mode: .rest, time: 1.25).cgPath
        if animated {
            ribbonMask.add(loop(keyPath: "path", duration: BreathRibbon.restLoop, frames: 40) {
                BreathRibbon.path(in: rect.size, energy: 0, mode: .rest, time: $0).cgPath
            }, forKey: "breath")
        }
    }

    /// A linear keyframe loop sampling `value` over one period; the render server plays it.
    private func loop(keyPath: String, duration: TimeInterval, frames: Int, value: (TimeInterval) -> Any) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0...frames).map { value(duration * Double($0) / Double(frames)) }
        animation.duration = duration
        animation.calculationMode = .linear
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    private func gcd(_ a: Double, _ b: Double) -> Double {
        var (x, y) = (Int(a), Int(b))
        while y != 0 { (x, y) = (y, x % y) }
        return Double(max(1, x))
    }

    /// Stops or resumes every loop where it is (Apple QA1673).
    /// While the page scrolls, the hero holds still: every scrolled frame would otherwise also
    /// recomposite this field's gradients and masks, and a long page then drops frames. It picks
    /// up again a moment after the last scroll event, and stays still if it has scrolled away.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        scrollResume?.cancel()
        scrollPaused = false
        updatePause()
        guard window != nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.scrolled(in: event.window)
            return event
        }
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollResume?.cancel()
    }

    private func scrolled(in eventWindow: NSWindow?) {
        guard eventWindow != nil, eventWindow === window else { return }
        if !scrollPaused {
            scrollPaused = true
            updatePause()
        }
        scrollResume?.cancel()
        let resume = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scrollPaused = false
            self.updatePause(checkVisible: true)
        }
        scrollResume = resume
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: resume)
    }

    private func updatePause(checkVisible: Bool = false) {
        // Scrolled out of view (nothing of it visible): no reason to animate either. Only checked
        // after a scroll, when the layout is settled.
        let hidden = checkVisible && window != nil && visibleRect.isEmpty
        setPaused(ownerPaused || scrollPaused || hidden)
    }

    private func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        let layer = root
        if paused {
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = now
        } else {
            let pausedAt = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }
}

extension Color {
    /// This colour fixed to its value in `environment`, so drawing it needs no further lookups.
    func flattened(in environment: EnvironmentValues) -> Color {
        Color(resolve(in: environment))
    }
}

// MARK: - Isolated hosting

/// Hosts `content` in its own `NSHostingView`, so a view that redraws every frame updates only
/// its own small view graph instead of laying out the whole window each time.
struct IsolatedHost<Content: View>: NSViewRepresentable {
    var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.sizingOptions = [] // sized by the parent; no constraint passes from inside
        return view
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) { nsView.rootView = content }
}

// MARK: - Window visibility

extension View {
    /// Calls `action` with whether the hosting window can be seen (on screen, not minimised or
    /// fully covered), so ambient motion can stop when nobody can see it.
    func onWindowVisibilityChange(_ action: @escaping (Bool) -> Void) -> some View {
        background(WindowVisibilityReader(onChange: action).frame(width: 0, height: 0))
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView(onChange: onChange) }

    func updateNSView(_ nsView: ReaderView, context: Context) { nsView.onChange = onChange }

    final class ReaderView: NSView {
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let window {
                let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification,
                                                   NSWindow.didMiniaturizeNotification,
                                                   NSWindow.didDeminiaturizeNotification,
                                                   NSWindow.willCloseNotification]
                observers = names.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                        if note.name == NSWindow.willCloseNotification {
                            self?.reportClosed()
                        } else {
                            self?.report()
                        }
                    }
                }
            }
            report()
        }

        private func reportClosed() {
            guard lastReported != false else { return }
            lastReported = false
            DispatchQueue.main.async { [onChange] in onChange(false) }
        }

        private func report() {
            let visible = window.map { $0.occlusionState.contains(.visible) && !$0.isMiniaturized } ?? false
            guard visible != lastReported else { return }
            lastReported = visible
            DispatchQueue.main.async { [onChange] in onChange(visible) }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

// MARK: - Live level

/// Reads the mic level inside its own body, so only this small view redraws with the voice
/// (about 47 times a second) and not the page, window or pill around it. Takes the
/// `AudioService` directly so it also works inside an `IsolatedHost`, which has no environment.
struct LiveLevel<Content: View>: View {
    let audio: AudioService
    @ViewBuilder var content: (Float) -> Content

    init(_ audio: AudioService, @ViewBuilder content: @escaping (Float) -> Content) {
        self.audio = audio
        self.content = content
    }

    var body: some View { content(audio.level) }
}
