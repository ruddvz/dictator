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
        let root = FloatingPillView { [weak self] size in self?.resize(to: size) }
            .environment(model)
        panel.contentView = FirstMouseHostingView(rootView: root)
        self.panel = panel
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct FloatingPillView: View {
    @Environment(AppModel.self) private var model
    var onSizeChange: (CGSize) -> Void

    @State private var isHovering = false

    private enum Phase { case idle, hover, listening, finishing }

    private var phase: Phase {
        if model.isFinalizingDictation || model.transcriber.isFinalizing { return .finishing }
        if model.audio.isRunning { return .listening }
        return isHovering ? .hover : .idle
    }

    var body: some View {
        pill
            .padding(6) // room for the shadow inside the transparent panel
            .fixedSize()
            .background(GeometryReader { geo in
                Color.clear.preference(key: PillSizeKey.self, value: geo.size)
            })
            .onPreferenceChange(PillSizeKey.self) { onSizeChange($0) }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: phase)
    }

    @ViewBuilder
    private var pill: some View {
        Button {
            Task { await model.toggleDictation() }
        } label: {
            content
                .background(Capsule().fill(.black.opacity(phase == .idle ? 0.55 : 0.88)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(phase == .idle ? 0 : 0.3), radius: 6, y: 2)
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
        switch phase {
        case .idle:
            Capsule().fill(.white.opacity(0.55))
                .frame(width: 28, height: 3)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        case .hover:
            HStack(spacing: 8) {
                Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold))
                Text(model.dictationCaptureBehavior == .hold
                     ? "Click or hold \(model.dictationShortcut.label)"
                     : "Click or press \(model.dictationShortcut.label)")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        case .listening:
            HStack(spacing: 10) {
                Circle().fill(Theme.listening).frame(width: 8, height: 8)
                LiveWaveform(level: model.audio.level, isActive: true, barCount: 18, tint: .white)
                    .frame(width: 92, height: 18)
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        case .finishing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle, .hover: "Start dictation"
        case .listening: "Listening. Stop dictation"
        case .finishing: "Transcribing"
        }
    }
}

private struct PillSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
