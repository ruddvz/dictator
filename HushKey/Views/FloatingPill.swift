import AppKit
import SwiftUI

/// Always-on-top dictation indicator at the bottom of the screen. It is a non-activating panel,
/// so clicking it never steals focus from the app that will receive the dictated text.
@MainActor
final class FloatingPillController {
    private var panel: NSPanel?
    private weak var model: AppModel?
    private var contentSize = CGSize(width: 60, height: 14)

    func attach(to model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        observe()
    }

    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.showsFloatingPill
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
            }
        }
        model.showsFloatingPill ? show() : hide()
    }

    private func show() {
        guard panel == nil, let model else { return }
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: contentSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        let root = FloatingPillView().environment(model)
        let hosting = FirstMouseHostingView(rootView: root)
        // Report size changes but let the controller own the frame, so the pill grows upward
        // from the bottom edge instead of downward from its top.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onIntrinsicSizeChange = { [weak self, weak hosting] in
            guard let hosting else { return }
            self?.resize(to: hosting.fittingSize)
        }
        panel.contentView = hosting
        self.panel = panel
        resize(to: hosting.fittingSize)
        place()
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        place()
    }

    private func place() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = CGPoint(x: visible.midX - contentSize.width / 2, y: visible.minY + 10)
        panel.setFrame(CGRect(origin: origin, size: contentSize), display: true)
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var onIntrinsicSizeChange: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onIntrinsicSizeChange?() }
    }
}

struct FloatingPillView: View {
    @Environment(AppModel.self) private var model

    @State private var isHovering = false
    @State private var showsDone = false

    private enum Phase { case idle, hover, listening, finishing, done }

    private var isFinishing: Bool { model.isFinalizingDictation || model.transcriber.isFinalizing }

    private var phase: Phase {
        if isFinishing { return .finishing }
        if model.audio.isRunning { return .listening }
        if showsDone { return .done }
        return isHovering ? .hover : .idle
    }

    var body: some View {
        pill
            .padding(6) // room for the shadow inside the transparent panel
            .fixedSize()
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: phase)
            .onChange(of: isFinishing) { wasFinishing, finishing in
                guard wasFinishing, !finishing, !model.transcriber.text.isEmpty else { return }
                showsDone = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    showsDone = false
                }
            }
    }

    private static let surface = Color(red: 0.078, green: 0.106, blue: 0.09)   // #141B17 sage-black
    private static let glow = Color(red: 0.61, green: 0.80, blue: 0.71)        // #9CCBB4 sage on dark

    private var pill: some View {
        content
            .foregroundStyle(.white)
            .background(Capsule().fill(Self.surface.opacity(phase == .idle ? 0.55 : 0.96)))
            .overlay(Capsule().strokeBorder(phase == .listening ? Self.glow.opacity(0.35) : .white.opacity(phase == .idle ? 0.22 : 0.1),
                                            lineWidth: phase == .listening ? 1 : 0.5))
            .shadow(color: phase == .listening ? Self.glow.opacity(0.25) : .black.opacity(phase == .idle ? 0 : 0.28),
                    radius: phase == .listening ? 12 : 8, y: 3)
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
            .onTapGesture {
                guard phase != .finishing else { return }
                Task { await model.toggleDictation() }
            }
            .help(phase == .listening ? "Click to finish" : "Start dictation (\(model.dictationShortcut.menuTitle))")
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        if phase == .idle {
            Capsule().fill(Self.glow.opacity(0.7))
                .frame(width: 24, height: 3)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .transition(.opacity)
        } else {
            HStack(spacing: 10) {
                switch phase {
                case .listening:
                    PillIconButton(systemImage: "xmark", help: "Cancel. Nothing is typed") { model.cancelDictation() }
                    VoiceRibbon(level: model.audio.level, isActive: true, tint: Self.glow)
                        .frame(width: 92, height: 20)
                    elapsed
                    PillIconButton(systemImage: "stop.fill", help: "Finish and type it") {
                        Task { await model.toggleDictation() }
                    }
                case .finishing:
                    MorphIcon(phase: .working, lineWidth: 1.8)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Self.glow)
                    Text("Writing it up").font(.system(size: 12, weight: .medium))
                case .done:
                    MorphIcon(phase: .done, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Self.glow)
                    Text(model.insertion.isEnabled ? "Typed" : "Copied to HushKey").font(.system(size: 12, weight: .medium))
                default:
                    MorphIcon(phase: .idle, lineWidth: 1.8)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Self.glow)
                    HStack(spacing: 4) {
                        Text(model.dictationShortcut.usesFunctionKey || model.dictationCaptureBehavior == .hold ? "Hold" : "Press")
                        Text(model.dictationShortcut.label).fontWeight(.semibold)
                        Text("or click to talk")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, phase == .listening ? 6 : 12)
            .padding(.vertical, phase == .listening ? 4 : 8)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private var elapsed: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(model.dictationStartedAt ?? context.date))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(minWidth: 28)
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle, .hover: "Start dictation"
        case .listening: "Listening. Stop dictation"
        case .finishing: "Transcribing"
        case .done: "Dictation finished"
        }
    }
}

/// Small round control inside the pill. Its own hit area, so it does not toggle dictation.
private struct PillIconButton: View {
    var systemImage: String
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.65))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(hovering ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
