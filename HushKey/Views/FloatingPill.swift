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

    private var morphPhase: MorphIcon.Phase {
        switch phase {
        case .idle, .hover: .idle
        case .listening: .listening
        case .finishing: .working
        case .done: .done
        }
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

    private var pill: some View {
        Button {
            Task { await model.toggleDictation() }
        } label: {
            content
                .foregroundStyle(.white)
                .background(Capsule().fill(Color(red: 0.1, green: 0.095, blue: 0.09).opacity(phase == .idle ? 0.6 : 0.94)))
                .overlay(Capsule().strokeBorder(.white.opacity(phase == .idle ? 0.25 : 0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(phase == .idle ? 0 : 0.28), radius: 8, y: 3)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(phase == .finishing)
        .onHover { isHovering = $0 }
        .help(phase == .listening ? "Stop dictation" : "Start dictation (\(model.dictationShortcut.label))")
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        if phase == .idle {
            Capsule().fill(.white.opacity(0.6))
                .frame(width: 26, height: 3)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .transition(.opacity)
        } else {
            HStack(spacing: 9) {
                MorphIcon(phase: morphPhase, level: model.audio.level, lineWidth: 1.8)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(phase == .listening ? Theme.listening : phase == .done ? Theme.success : .white)
                switch phase {
                case .listening:
                    LiveWaveform(level: model.audio.level, isActive: true, barCount: 16, tint: .white)
                        .frame(width: 76, height: 16)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                case .finishing:
                    Text("Transcribing").font(.system(size: 12, weight: .medium))
                case .done:
                    Text(model.insertion.isEnabled ? "Ready to insert" : "Done").font(.system(size: 12, weight: .medium))
                default:
                    HStack(spacing: 4) {
                        Text(model.dictationCaptureBehavior == .hold ? "Hold" : "Press")
                        Text(model.dictationShortcut.label).fontWeight(.semibold)
                        Text("or click")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
