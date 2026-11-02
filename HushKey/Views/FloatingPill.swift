import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Always-on-top dictation indicator at the bottom of the screen. It is a non-activating panel,
/// so clicking it never steals focus from the app that will receive the dictated text.
@MainActor
final class FloatingPillController {
    private var panel: NSPanel?
    private weak var model: AppModel?
    private var contentSize = CGSize(width: 60, height: 14)
    private var escapeMonitors: [Any] = []

    func attach(to model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        observe()
    }

    private func observe() {
        guard let model else { return }
        withObservationTracking {
            _ = model.showsFloatingPill
            _ = model.showsFinishedTranscript
            _ = model.audio.isRunning
            _ = model.audio.isStarting
            _ = model.isStartingDictation
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
            }
        }
        model.showsFloatingPill ? show() : hide()
        let cardIsUp = model.showsFloatingPill && model.showsFinishedTranscript
        cardIsUp || model.audio.isRunning || model.isStartingDictation ? watchEscape() : stopWatchingEscape()
    }

    /// Esc cancels a dictation that is listening (nothing is typed) and closes the finished
    /// transcript card. The panel never takes key focus, so watch the key in other apps (needs
    /// the Accessibility access fn already uses) and in HushKey. Idea from amirrsyed/hushkey (MIT).
    private func watchEscape() {
        guard escapeMonitors.isEmpty else { return }
        let dismiss: (NSEvent) -> Bool = { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return false }
            Task { @MainActor in
                guard let model = self?.model else { return }
                if model.isStartingDictation || model.audio.isRunning { model.cancelDictation() }
                else { model.dismissFinishedTranscript() }
            }
            return true
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = dismiss($0) }) {
            escapeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { dismiss($0) ? nil : $0 }) {
            escapeMonitors.append(local)
        }
    }

    private func stopWatchingEscape() {
        escapeMonitors.forEach(NSEvent.removeMonitor)
        escapeMonitors = []
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
        panel.appearance = NSAppearance(named: .darkAqua) // the pill is always dark, so tokens resolve to dark values
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
    @State private var doneToken = 0
    @State private var cardCollapsed = false
    @State private var copied = false

    private enum Phase { case idle, hover, preparing, listening, finishing, error, done }

    private var isFinishing: Bool { model.isFinalizingDictation || model.transcriber.isFinalizing }

    private var phase: Phase {
        if isFinishing { return .finishing }
        if model.isStartingDictation { return .preparing }
        if model.audio.isRunning { return .listening }
        if model.dictationNotice != nil { return .error }
        if showsDone { return .done }
        return isHovering ? .hover : .idle
    }

    private var cardState: TranscriptCard.State {
        TranscriptCard.state(isCapturing: model.audio.isRunning || isFinishing, hasTarget: model.dictationHasTarget,
                             transcript: model.transcriber.text, isCollapsed: cardCollapsed,
                             keepsFinishedText: model.showsFinishedTranscript)
    }

    var body: some View {
        VStack(spacing: 8) {
            if cardState != .hidden {
                transcriptCard
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            pill
        }
            .padding(6) // room for the shadow inside the transparent panel
            .fixedSize()
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: phase)
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: cardState)
            .onChange(of: model.audio.isRunning) { _, running in
                if running {
                    cardCollapsed = false
                    copied = false
                }
            }
            .onChange(of: model.completedDictationCount) {
                doneToken += 1
                let token = doneToken
                showsDone = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    if token == doneToken { showsDone = false }
                }
            }
    }

    private static let surface = Color(red: 0.078, green: 0.106, blue: 0.09)   // #141B17 sage-black
    private static let glow = Color(red: 0.61, green: 0.80, blue: 0.71)        // #9CCBB4 sage on dark

    private var pill: some View {
        content
            .foregroundStyle(.white)
            .background(Capsule().fill(Self.surface.opacity(phase == .idle ? 0.55 : 0.96)))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: phase == .listening || phase == .error ? 1 : 0.5))
            .shadow(color: shadow, radius: phase == .listening ? 12 : 8, y: 3)
            .contentShape(Capsule())
            .onHover { isHovering = $0 }
            .onTapGesture { press() }
            .help(help)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { press() } // VoiceOver and other assistive presses
    }

    private var shadow: Color {
        phase == .listening ? Self.glow.opacity(0.25) : .black.opacity(phase == .idle ? 0 : 0.28)
    }

    private func press() {
        // An error only goes away through its own controls, so a stray click cannot start recording.
        guard phase != .finishing, phase != .error else { return }
        Task { await model.toggleDictation() }
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
                case .preparing:
                    MorphIcon(phase: .working, lineWidth: 1.8)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Self.glow)
                    Text(model.audio.isStarting ? "Waiting for microphone" : "Preparing locally")
                        .font(.system(size: 13, weight: .medium))
                    PillIconButton(systemImage: "xmark", title: "Cancel", help: "Cancel before the microphone starts") {
                        model.cancelDictation()
                    }
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
                    Text("Writing it up").font(.system(size: 13, weight: .medium))
                case .error:
                    if let notice = model.dictationNotice { errorContent(notice) }
                case .done:
                    MorphIcon(phase: .done, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Self.glow)
                    Text(model.didInsertCurrentDictation ? "Typed" : "Ready in HushKey").font(.system(size: 13, weight: .medium))
                default:
                    MorphIcon(phase: .idle, lineWidth: 1.8)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Self.glow)
                    HStack(spacing: 4) {
                        Text(model.dictationShortcut.usesFunctionKey || model.dictationCaptureBehavior == .hold ? "Hold" : "Press")
                        Text(model.dictationShortcut.label).fontWeight(.semibold)
                        Text("or click to talk")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
            .padding(.leading, phase == .listening ? 6 : phase == .error ? 10 : 12)
            .padding(.trailing, phase == .listening || phase == .error ? 6 : 12)
            .padding(.vertical, phase == .listening || phase == .error ? 4 : 8)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// Live text above the pill while talking; with no text field to type into, it stays up
    /// after finishing with Copy and close.
    private var transcriptCard: some View {
        let state = cardState
        let isFinished: Bool
        let hint: String?
        switch state {
        case .finished(let value): isFinished = true; hint = value
        case .live(let value): isFinished = false; hint = value
        case .hidden: isFinished = false; hint = nil
        }
        let text = TranscriptCard.tail(model.transcriber.text)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MorphIcon(phase: isFinished ? .done : .listening, lineWidth: 1.8)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Self.glow)
                Spacer(minLength: 8)
                if let hint = model.insertion.isEnabled || !isFinished ? hint : "Typing into apps is off" {
                    Text(hint)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                PillIconButton(systemImage: "xmark", help: isFinished ? "Close (Esc)" : "Hide live text") {
                    if isFinished { model.dismissFinishedTranscript() } else { cardCollapsed = true }
                }
            }
            Text(text.isEmpty ? "Listening…" : text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(text.isEmpty ? 0.4 : 1))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if isFinished {
                HStack(spacing: 8) {
                    if !model.insertion.isEnabled {
                        Button("Type for me next time") {
                            UserDefaults.standard.set(SettingsView.Section.insertion.rawValue, forKey: "settingsSection")
                            model.screen = .settings
                            NSApp.activate(ignoringOtherApps: true)
                            model.dismissFinishedTranscript()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Self.glow)
                        .help("Turn on typing into the focused text box")
                    }
                    Spacer()
                    Button {
                        model.copyDictationText()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Self.glow, foreground: Self.surface))
                    .keyboardShortcut("c", modifiers: .command)
                    .help("Copy to the clipboard (⌘C)")
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous).fill(Self.surface.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous)
            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isFinished ? "Finished transcript" : "Live transcript")
    }

    @ViewBuilder
    private func errorContent(_ notice: DictationNotice) -> some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.danger)
        Text(notice.message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.danger)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 190, alignment: .leading)
        if notice.canRetry {
            PillIconButton(systemImage: "arrow.clockwise", title: "Retry",
                           help: "Transcribe the last recording again") {
                Task { await model.retryDictation() }
            }
        }
        if notice.canPasteAgain {
            PillIconButton(systemImage: "text.insert", title: "Paste again",
                           help: notice.message == "Check the field first"
                               ? "Check \(model.capturedInsertionTargetName ?? "the original app") first. Retry only if the transcript is missing; it may already have arrived."
                               : "Type it again, only if \(model.capturedInsertionTargetName ?? "the original app") still has focus") {
                Task { await model.pasteLastDictationAgain() }
            }
        }
        PillIconButton(systemImage: "xmark", help: "Dismiss", tint: Theme.danger) { model.dismissDictationNotice() }
    }

    private var stroke: Color {
        switch phase {
        case .listening: Self.glow.opacity(0.35)
        case .error: Theme.danger.opacity(0.45)
        case .idle: .white.opacity(0.22)
        default: .white.opacity(0.1)
        }
    }

    private var help: String {
        switch phase {
        case .listening: "Click to finish"
        case .preparing: "Preparing local speech recognition. Click to cancel."
        case .error: model.dictationNotice?.detail ?? ""
        default: "Start dictation (\(model.dictationShortcut.menuTitle))"
        }
    }

    private var elapsed: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(model.dictationStartedAt ?? context.date))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(minWidth: 28)
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle, .hover: "Start dictation"
        case .preparing: "Preparing local speech recognition. Cancel dictation startup"
        case .listening: "Listening. Stop dictation"
        case .finishing: "Transcribing"
        case .error: "Dictation problem: \(model.dictationNotice?.message ?? ""). \(model.dictationNotice?.detail ?? "")"
        case .done: "Dictation finished"
        }
    }
}

/// Small round control inside the pill. Its own hit area, so it does not toggle dictation.
/// With a title it becomes a short capsule in the same style, for recovery actions.
private struct PillIconButton: View {
    var systemImage: String
    var title: String? = nil
    var help: String
    var tint: Color = .white
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                if let title {
                    Text(title).font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(tint.opacity(hovering ? 0.95 : 0.65))
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, title == nil ? 0 : 9)
            .background(Capsule().fill(tint.opacity(hovering ? 0.16 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
