import AppKit
import SwiftUI

/// A small dark tag above the dictation pill while Control captures a silent word in another app,
/// then what happened to it: typed, not sure, too short. Without it a capture outside Dictator gave
/// no sign at all. It never takes focus or clicks, and stays hidden while Dictator is in front,
/// where Train and Silent Use already show the same thing.
@MainActor
final class SilentCaptureHUDController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var hosting: NSHostingView<SilentCaptureHUDView>?
    private var lastFeedbackID: UUID?
    private var hideWork: DispatchWorkItem?

    /// How long an outcome stays up.
    static let outcomeSeconds: TimeInterval = 1.6
    /// Height above the bottom of the screen, clear of the dictation pill.
    static let bottomOffset: CGFloat = 56

    func attach(to model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        observe()
    }

    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.capture.isCapturing
            _ = model.capture.headIsMoving
            _ = model.silentFeedback
            _ = model.screen
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        update(model)
    }

    private func update(_ model: AppModel) {
        let inLab = model.screen == .train || model.screen == .use
        guard inLab, !NSApp.isActive else {
            lastFeedbackID = model.silentFeedback?.id
            hide()
            return
        }
        if model.capture.isCapturing {
            let prompt = model.screen == .train ? model.selectedWord.map { "Mouth “\($0)”…" } : nil
            show(model.capture.headIsMoving ? .headMoving : .capturing(prompt ?? "Mouth a word…"), autoHide: false)
        } else if let feedback = model.silentFeedback, feedback.id != lastFeedbackID {
            lastFeedbackID = feedback.id
            show(.outcome(feedback), autoHide: true)
        } else if hideWork == nil {
            hide() // a capture ended without an outcome, such as ⌃C cancelling it
        }
    }

    private func show(_ state: SilentCaptureHUDView.State, autoHide: Bool) {
        hideWork?.cancel()
        hideWork = nil
        let view = SilentCaptureHUDView(state: state)
        if let hosting {
            hosting.rootView = view
        } else {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.appearance = NSAppearance(named: .darkAqua) // always dark, like the pill
            let hosting = NSHostingView(rootView: view)
            panel.contentView = hosting
            self.panel = panel
            self.hosting = hosting
        }
        place()
        panel?.orderFrontRegardless()
        guard autoHide else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hideWork = nil
            self?.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.outcomeSeconds, execute: work)
    }

    private func place() {
        guard let panel, let hosting else { return }
        let size = hosting.fittingSize
        let visible = (PillPlacement.screenUnderPointer() ?? NSScreen.main)?.visibleFrame ?? .zero
        let x = visible.minX + visible.width * PillPlacement.storedFraction - size.width / 2
        let clampedX = min(max(x, visible.minX + PillPlacement.edgeInset), visible.maxX - PillPlacement.edgeInset - size.width)
        panel.setFrame(CGRect(x: clampedX, y: visible.minY + Self.bottomOffset, width: size.width, height: size.height),
                       display: true)
    }

    private func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }
}

struct SilentCaptureHUDView: View {
    enum State: Equatable {
        case capturing(String)
        case headMoving
        case outcome(SilentCaptureFeedback)
    }

    var state: State

    var body: some View {
        HStack(spacing: Theme.s2) {
            SymbolGlyph(symbol, size: Theme.iconM)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: isCapturing)
            Text(text)
                .font(isTyped ? .hkControl.weight(.semibold) : .hkControl)
                .foregroundStyle(isQuiet ? Theme.ink2 : Theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.s3)
        .frame(height: Theme.fieldHeight)
        .background(Theme.sheet, in: Capsule())
        .overlay(Capsule().strokeBorder(isCapturing ? Theme.signalEdge : Theme.hairline, lineWidth: Theme.hairlineWidth))
        .fixedSize()
        .padding(Theme.s1) // room for the border
        .accessibilityElement(children: .combine)
    }

    private var isCapturing: Bool {
        switch state {
        case .capturing, .headMoving: true
        case .outcome: false
        }
    }

    private var kind: SilentCaptureFeedback.Kind? {
        if case .outcome(let feedback) = state { feedback.kind } else { nil }
    }

    private var isTyped: Bool { kind == .typed }
    private var isQuiet: Bool { kind == .unsure || kind == .ignored }

    private var text: String {
        switch state {
        case .capturing(let prompt): prompt
        case .headMoving: "Keep your head still"
        case .outcome(let feedback): feedback.text
        }
    }

    private var symbol: String {
        if state == .headMoving { return "exclamationmark.triangle" }
        return switch kind {
        case nil: "waveform.path"
        case .typed, .saved: "checkmark"
        case .notTyped: "text.badge.xmark"
        case .unsure: "questionmark"
        case .ignored: "minus"
        case .problem: "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        if state == .headMoving { return Theme.finishing }
        return switch kind {
        case nil, .typed, .saved: Theme.signal
        case .notTyped, .problem: Theme.finishing
        case .unsure, .ignored: Theme.ink3
        }
    }
}
