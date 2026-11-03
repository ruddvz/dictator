import AppKit
import Carbon.HIToolbox
import CoreAudio
import SwiftUI

/// Always-on-top dictation indicator at the bottom of the screen. It is a non-activating panel,
/// so clicking it never steals focus from the app that will receive the dictated text.
@MainActor
final class FloatingPillController {
    private var panel: NSPanel?
    private weak var model: AppModel?
    private var contentSize = CGSize(width: 60, height: 14)
    /// A smaller size waits for the closing animation, so the panel never clips the pill as it shrinks.
    private var pendingShrink: DispatchWorkItem?
    private var escapeMonitors: [Any] = []
    /// The screen the pill sits on: wherever the pointer was when it appeared or a dictation began.
    private var screen: NSScreen?
    private var wasCapturing = false
    /// Pointer x and pill centre when a drag began.
    private var dragStart: (mouseX: CGFloat, centerX: CGFloat)?
    /// Where along the bottom edge the pill sits, 0…1 of the screen width; remembered.
    private var centerFraction = PillPlacement.storedFraction

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
        let capturing = model.audio.isRunning || model.audio.isStarting || model.isStartingDictation
        if capturing, !wasCapturing {
            screen = PillPlacement.screenUnderPointer()
            place()
        }
        wasCapturing = capturing
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
                if model.isStartingDictation || model.audio.isRunning { model.cancelDictation(offersUndo: true) }
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
        let root = FloatingPillView(onDrag: { [weak self] in self?.drag(ended: $0) },
                                    onCentre: { [weak self] in self?.moveToCentre() },
                                    onSize: { [weak self] size in
                                        // After the layout pass that measured it: resizing the panel
                                        // from inside AppKit's constraint pass aborts the app.
                                        DispatchQueue.main.async { self?.resize(to: size) }
                                    })
            .environment(model)
            // While the panel is still larger than the pill (see `resize`), keep the pill on the bottom edge.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        let hosting = FirstMouseHostingView(rootView: root)
        // The controller owns the frame, so the pill grows upward from the bottom edge. With no
        // sizing options the hosting view never drives the window size or constraints itself.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        let container = NSView(frame: CGRect(origin: .zero, size: contentSize))
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel
        screen = PillPlacement.screenUnderPointer()
        resize(to: hosting.fittingSize)
        place()
        panel.orderFrontRegardless()
    }

    private func hide() {
        pendingShrink?.cancel()
        pendingShrink = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Grows at once, before the opening animation is drawn, and shrinks only once the closing
    /// animation has settled. Resizing a window mid-animation clips the pill or makes it flicker.
    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        pendingShrink?.cancel()
        pendingShrink = nil
        let grown = CGSize(width: max(size.width, contentSize.width), height: max(size.height, contentSize.height))
        apply(grown)
        guard grown != size else { return }
        let shrink = DispatchWorkItem { [weak self] in self?.apply(size) }
        pendingShrink = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: shrink)
    }

    private func apply(_ size: CGSize) {
        guard size != contentSize else { return }
        contentSize = size
        place()
    }

    private func place() {
        guard let panel, let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let origin = PillPlacement.origin(size: contentSize, in: screen.visibleFrame, centerFraction: centerFraction)
        let frame = CGRect(origin: origin, size: contentSize)
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: false)
    }

    private func moveToCentre() {
        centerFraction = 0.5
        PillPlacement.storedFraction = centerFraction
        place()
    }

    /// Slides the pill along the bottom edge with the pointer, then remembers where it was left.
    private func drag(ended: Bool) {
        guard let panel, let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let mouseX = NSEvent.mouseLocation.x
        let start = dragStart ?? (mouseX, panel.frame.midX)
        dragStart = ended ? nil : start
        centerFraction = PillPlacement.snapped(PillPlacement.fraction(centerX: start.centerX + mouseX - start.mouseX,
                                                                      width: contentSize.width, in: visible))
        place()
        if ended { PillPlacement.storedFraction = centerFraction }
    }
}

/// Where the pill sits: centred on a remembered fraction of the screen width, 10 pt above the
/// bottom of the visible frame, and never past either edge.
enum PillPlacement {
    static let bottomInset: CGFloat = 8 // plus the view's 8 pt shadow margin: the pill sits 16 pt up
    static let edgeInset: CGFloat = 8
    private static let key = "pillCenterFraction"

    static var storedFraction: CGFloat {
        get { (UserDefaults.standard.object(forKey: key) as? Double).map { CGFloat($0) } ?? 0.5 }
        set { UserDefaults.standard.set(Double(newValue), forKey: key) }
    }

    static func origin(size: CGSize, in visible: CGRect, centerFraction: CGFloat) -> CGPoint {
        let centerX = visible.minX + visible.width * min(1, max(0, centerFraction))
        let lowest = visible.minX + edgeInset
        let highest = max(lowest, visible.maxX - edgeInset - size.width)
        return CGPoint(x: min(highest, max(lowest, centerX - size.width / 2)), y: visible.minY + bottomInset)
    }

    /// The fraction for a pill centred at `centerX`, clamped so the pill stays on screen.
    static func fraction(centerX: CGFloat, width: CGFloat, in visible: CGRect) -> CGFloat {
        guard visible.width > 0 else { return 0.5 }
        let half = width / 2 + edgeInset
        let clamped = min(visible.maxX - half, max(visible.minX + half, centerX))
        return (clamped - visible.minX) / visible.width
    }

    /// Dropped near the middle, the pill clicks back to the centre.
    static func snapped(_ fraction: CGFloat) -> CGFloat {
        abs(fraction - 0.5) < 0.06 ? 0.5 : fraction
    }

    static func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct FloatingPillView: View {
    @Environment(AppModel.self) private var model
    /// Dragging slides the pill along the bottom edge; `true` when the drag ends.
    var onDrag: (Bool) -> Void = { _ in }
    /// Puts the pill back in the middle of the bottom edge.
    var onCentre: () -> Void = {}
    /// The pill's measured size, so the panel can fit it.
    var onSize: (CGSize) -> Void = { _ in }

    @State private var isHovering = false
    /// After a few quiet seconds the idle bar shrinks to a dot, out of the way.
    @State private var idleIsCompact = false
    @State private var hoveredControl: PillControl?
    @State private var showsDone = false
    @State private var doneToken = 0
    @State private var cardCollapsed = false
    @State private var copied = false

    private enum Phase { case idle, hover, preparing, listening, finishing, error, done }
    private enum PillControl { case cancel, finish, notes }

    private var isFinishing: Bool { model.isFinalizingDictation || model.transcriber.isFinalizing }

    private var phase: Phase {
        if isFinishing { return .finishing }
        // The microphone buffers while recognition gets ready, so show the live meter at once.
        if model.audio.isRunning { return .listening }
        if model.isStartingDictation { return .preparing }
        if model.dictationNotice != nil { return .error }
        if showsDone { return .done }
        return isHovering ? .hover : .idle
    }

    /// Hold to talk keeps a hand on the key, so the pill is just the meter; click and
    /// hands-free dictation get cancel and finish controls.
    private var showsControls: Bool {
        (phase == .listening || phase == .preparing) && !model.dictationShortcutHeld
    }

    private var cardState: TranscriptCard.State {
        TranscriptCard.state(isCapturing: model.audio.isRunning || isFinishing, hasTarget: model.dictationHasTarget,
                             transcript: model.transcriber.text, isCollapsed: cardCollapsed,
                             keepsFinishedText: model.showsFinishedTranscript)
    }

    var body: some View {
        VStack(spacing: Theme.s2) {
            if cardState != .hidden {
                transcriptCard
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let hint {
                PillHint(title: hint.title, shortcut: hint.shortcut)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
            pill
        }
            .padding(8) // room for the shadow inside the transparent panel
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: phase)
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: cardState)
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: showsControls)
            .animation(Theme.snappy, value: hint)
            .onChange(of: model.audio.isRunning) { _, running in
                if running {
                    cardCollapsed = false
                    copied = false
                }
            }
            .onChange(of: phase) { hoveredControl = nil }
            .task(id: phase) {
                idleIsCompact = false
                guard phase == .idle else { return }
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { idleIsCompact = true }
            }
            .onChange(of: model.completedDictationCount) {
                doneToken += 1
                let token = doneToken
                showsDone = true
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    if token == doneToken { showsDone = false }
                }
            }
    }

    private var pill: some View {
        content
            .foregroundStyle(Theme.ink)
            .background(Capsule().fill(Theme.paper.opacity(phase == .idle ? 0.82 : 1)))
            // The capsule grows around its contents; clipping reveals them instead of letting them spill.
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(stroke, lineWidth: phase == .error && model.dictationNotice?.isNeutral != true ? 1 : 0.5))
            // A faint shadow at rest lifts the bar off light desktops; the hairline does it on dark ones.
            .shadow(color: .black.opacity(phase == .idle ? 0.18 : 0.32), radius: phase == .idle ? 3 : 6, y: phase == .idle ? 1 : 2)
            .contentShape(Capsule())
            .onHover { inside in
                isHovering = inside
                if inside { model.audio.refreshDevices() }
            }
            .onTapGesture { press() }
            .gesture(DragGesture(minimumDistance: 10) // a slightly shaky click should not move it
                .onChanged { _ in onDrag(false) }
                .onEnded { _ in onDrag(true) })
            .contextMenu { pillMenu }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { press() } // VoiceOver and other assistive presses
    }

    private func press() {
        // An error only goes away through its own controls, so a stray click cannot start recording.
        guard phase != .finishing, phase != .error else { return }
        Task { await model.toggleDictation() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Capsule().fill(Theme.signal.opacity(idleIsCompact ? 0.6 : 0.85))
                .frame(width: idleIsCompact ? 8 : 20, height: 3)
                .padding(.horizontal, idleIsCompact ? 7 : 12)
                .padding(.vertical, 5)
                .animation(Theme.gentle, value: idleIsCompact)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
        case .hover:
            hoverBar
                // Fade in once the capsule has mostly opened, so nothing is drawn squashed.
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.07)),
                                        removal: .opacity.animation(.easeOut(duration: 0.1))))
        case .preparing, .listening, .finishing:
            recorder
        case .error:
            HStack(spacing: 10) {
                if let notice = model.dictationNotice { errorContent(notice) }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .done:
            // The success cue says it landed; the pill only closes its line into a check.
            MorphIcon(phase: .done, lineWidth: 2)
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.signal)
                .padding(.horizontal, Theme.s3)
                .frame(height: Self.height)
                .accessibilityLabel(model.didInsertCurrentDictation ? "Typed" : "Ready to copy")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private static let height: CGFloat = 28

    /// The idle bar opened by the pointer: the whole capsule is the dictate button, labelled with
    /// its key, and a quiet Meeting notes button sits after a hairline. One shape, no tooltip.
    private var hoverBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                MorphIcon(phase: .idle, lineWidth: 1.6)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.signal)
                Text("Dictate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                PillKey(label: model.dictationShortcut.label)
            }
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .opacity(hoveredControl == .notes ? 0.55 : 1)
            .animation(Theme.snappy, value: hoveredControl)
            Rectangle()
                .fill(Theme.ink.opacity(0.14))
                .frame(width: 1, height: 14)
            PillIconButton(systemImage: "person.2.wave.2", help: "Open Meeting notes", quiet: true, size: 24,
                           onHover: { hoveredControl = $0 ? .notes : nil }) {
                model.openMeetingNotes()
            }
            .padding(.leading, 4)
            .padding(.trailing, 5) // the glyph then sits as far from the edge as the hush does
        }
        .frame(height: Self.height)
        .fixedSize()
    }

    /// One capsule from the first press to the typed text: the meter waits, listens, then works,
    /// so the pill never jumps between shapes mid-dictation.
    private var recorder: some View {
        HStack(spacing: 6) {
            if showsControls {
                PillIconButton(systemImage: "xmark", help: phase == .preparing ? "Cancel before the microphone starts" : "Cancel. Nothing is typed",
                               onHover: { hoveredControl = $0 ? .cancel : nil }) {
                    model.cancelDictation(offersUndo: true)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            let ribbonMode: BreathRibbon.Mode = phase == .listening ? .live : phase == .preparing ? .waiting : .working
            LiveLevel(model.audio) { BreathRibbon(level: $0, mode: ribbonMode, tint: Theme.ink) }
                .frame(width: 58, height: 18)
                .padding(.horizontal, showsControls ? 2 : 6)
            if phase == .listening { elapsed }
            if showsControls {
                PillIconButton(systemImage: "checkmark", help: "Finish and type it", prominent: true,
                               onHover: { hoveredControl = $0 ? .finish : nil }) {
                    Task { await model.toggleDictation() }
                }
                .disabled(phase == .preparing)
                .opacity(phase == .preparing ? 0.35 : 1)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .padding(.horizontal, showsControls ? 4 : 8)
        .frame(height: Self.height)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    /// Short tooltip above the pill: what a hovered control does and its key, or what the pill
    /// is waiting for. Shown at once, unlike a system tooltip in a non-activating panel.
    private var hint: PillHint.Content? {
        switch hoveredControl {
        case .cancel?: return .init(title: "Cancel", shortcut: "esc")
        case .finish?: return .init(title: "Finish", shortcut: model.dictationShortcut.label)
        case .notes?: return .init(title: "Meeting notes", shortcut: nil)
        case nil: break
        }
        switch phase {
        case .preparing:
            if model.audio.isAwaitingPermission || model.transcriber.isAwaitingPermission {
                return .init(title: "Answer the macOS prompt", shortcut: nil)
            }
            return .init(title: model.audio.isStarting ? "Waiting for microphone" : "Preparing locally", shortcut: nil)
        default: return nil
        }
    }

    /// Live text above the pill while talking; with no text field to type into, it stays up
    /// after finishing with Copy and close.
    @ViewBuilder
    private var transcriptCard: some View {
        let (isFinished, hint): (Bool, String?) = switch cardState {
        case .finished(let value): (true, value)
        case .live(let value): (false, value)
        case .hidden: (false, nil)
        }
        let text = TranscriptCard.tail(model.transcriber.text)
        let shownHint = model.insertion.isEnabled || !isFinished ? hint : "Typing into apps is off"
        if text.isEmpty {
            // Nothing said yet: a one-line strip, not an empty card with a placeholder headline.
            HStack(spacing: Theme.s2) {
                LiveLevel(model.audio) { MorphIcon(phase: .listening, level: $0, lineWidth: 1.6) }
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.signal)
                if let shownHint {
                    Text(shownHint)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
                PillIconButton(systemImage: "xmark", help: "Hide live text", size: 18) { cardCollapsed = true }
            }
            .padding(.leading, Theme.s3)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.paper))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Live transcript")
        } else {
            VStack(alignment: .leading, spacing: Theme.s2) {
                HStack(spacing: Theme.s2) {
                    LiveLevel(model.audio) { MorphIcon(phase: isFinished ? .done : .listening, level: $0, lineWidth: 1.6) }
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.signal)
                    if let shownHint {
                        Text(shownHint)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Theme.s2)
                    PillIconButton(systemImage: "xmark", help: isFinished ? "Close (Esc)" : "Hide live text", size: 18) {
                        if isFinished { model.dismissFinishedTranscript() } else { cardCollapsed = true }
                    }
                }
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                if isFinished {
                    HStack(spacing: Theme.s2) {
                        if !model.insertion.isEnabled {
                            Button("Type for me next time") {
                                UserDefaults.standard.set(SettingsView.Section.insertion.rawValue, forKey: "settingsSection")
                                model.screen = .settings
                                NSApp.activate(ignoringOtherApps: true)
                                model.dismissFinishedTranscript()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.signal)
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
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.signal, foreground: Theme.paper))
                        .keyboardShortcut("c", modifiers: .command)
                        .help("Copy to the clipboard (⌘C)")
                    }
                }
            }
            .padding(Theme.s3)
            .frame(width: 320)
            .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous).fill(Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(isFinished ? "Finished transcript" : "Live transcript")
        }
    }

    @ViewBuilder
    private func errorContent(_ notice: DictationNotice) -> some View {
        let tint = notice.isNeutral ? Theme.ink2 : Theme.danger
        Image(systemName: notice.isNeutral ? "arrow.uturn.backward.circle" : "exclamationmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
        Text(notice.message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 190, alignment: .leading)
            .help(notice.detail)
        if notice.kind == .cancelled {
            PillIconButton(systemImage: "arrow.uturn.backward", title: "Undo",
                           help: "Transcribe what you said and type it") {
                Task { await model.retryDictation() }
            }
        } else if notice.canRetry {
            PillIconButton(systemImage: "arrow.clockwise", title: "Retry",
                           help: "Transcribe the last recording again") {
                Task { await model.retryDictation() }
            }
        }
        if notice.offersMicrophoneHelp {
            Menu {
                microphoneChoices
            } label: {
                Label("Mic", systemImage: "mic")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .font(.system(size: 12, weight: .semibold))
            .help("Choose the microphone")
            .accessibilityLabel("Choose the microphone")
            PillIconButton(systemImage: "slider.horizontal.3", help: "Open Sound settings to check the input") {
                model.openSoundInputSettings()
            }
        }
        if let privacy = notice.missingPermission {
            PillIconButton(systemImage: "lock.open", title: "Open Settings",
                           help: "Open Privacy & Security settings", prominent: true) {
                model.openPrivacySettings(privacy)
                model.dismissDictationNotice()
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
        PillIconButton(systemImage: "xmark", help: "Dismiss", tint: tint) { model.dismissDictationNotice() }
    }

    /// The inputs HushKey can listen to, with the current one checked.
    @ViewBuilder
    private var microphoneChoices: some View {
        Picker("Microphone", selection: Binding(get: { model.audio.selectedDeviceID },
                                                set: { model.audio.selectedDeviceID = $0 })) {
            Text("System default").tag(AudioDeviceID?.none)
            ForEach(model.audio.devices) { device in
                Text(device.name).tag(Optional(device.id))
            }
        }
        .pickerStyle(.inline)
    }

    /// Right-click menu: microphone, sounds, and getting back to HushKey.
    @ViewBuilder
    private var pillMenu: some View {
        microphoneChoices
        Toggle("Dictation sounds", isOn: Binding(get: { model.playsDictationSounds },
                                                       set: { model.playsDictationSounds = $0 }))
        Divider()
        Button("Move to the center") { onCentre() }
        Button("Meeting notes") { model.openMeetingNotes() }
        Button("Open HushKey") {
            model.screen = .dictation
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Hide the dictation bar") { model.showsFloatingPill = false }
    }

    private var stroke: Color {
        switch phase {
        case .error: model.dictationNotice?.isNeutral == true ? Theme.ink.opacity(0.12) : Theme.danger.opacity(0.45)
        case .idle: Theme.ink.opacity(0.22)
        default: Theme.ink.opacity(0.12)
        }
    }

    /// Elapsed time, only once a dictation runs long enough for it to help.
    private var elapsed: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(model.dictationStartedAt ?? context.date))
            if seconds >= 30 {
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.ink2)
                    .padding(.trailing, 2)
            }
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle, .hover: "Start dictation"
        case .preparing: "Preparing local speech recognition. Cancel dictation startup"
        case .listening: model.dictationShortcutHeld ? "Listening. Release \(model.dictationShortcut.label) to finish" : "Listening. Stop dictation"
        case .finishing: "Transcribing"
        case .error:
            model.dictationNotice?.isNeutral == true
                ? "Dictation cancelled. \(model.dictationNotice?.detail ?? "")"
                : "Dictation problem: \(model.dictationNotice?.message ?? ""). \(model.dictationNotice?.detail ?? "")"
        case .done: "Dictation finished"
        }
    }
}

/// The tooltip that floats above the pill.
private struct PillHint: View {
    struct Content: Equatable {
        var title: String
        var shortcut: String?
    }

    var title: String
    var shortcut: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
            if let shortcut { PillKey(label: shortcut) }
        }
        .padding(.leading, 10)
        .padding(.trailing, shortcut == nil ? 10 : 4)
        .frame(height: 24)
        .background(Capsule().fill(Theme.paper))
        .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
        .accessibilityHidden(true) // the controls carry their own labels
    }
}

/// A shortcut as one small key ("fn", "esc", "⌥⇧D"), in the sage keycap colours.
private struct PillKey: View {
    var label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(Theme.keycap))
            .overlay(RoundedRectangle(cornerRadius: 4.5, style: .continuous).strokeBorder(Theme.keycapEdge, lineWidth: 0.5))
            .accessibilityLabel("Shortcut \(label)")
    }
}

/// Small round control inside the pill. Its own hit area, so it does not toggle dictation.
/// Prominent controls are filled sage (the one primary action); with a title it becomes a
/// short capsule in the same style, for recovery actions.
private struct PillIconButton: View {
    var systemImage: String
    var title: String? = nil
    var help: String
    var tint: Color = Theme.ink
    var prominent = false
    /// No fill until hovered, for a secondary control beside the pill's main action.
    var quiet = false
    var size: CGFloat = 20
    /// Reports hover to the pill, which shows its own hint instead of a slow system tooltip.
    var onHover: ((Bool) -> Void)? = nil
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: quiet ? 11 : prominent ? 10 : 9, weight: quiet ? .semibold : .bold))
                if let title {
                    Text(title).font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(prominent ? Theme.paper : tint.opacity(hovering ? 0.95 : 0.7))
            .frame(minWidth: title == nil ? size : 24, minHeight: title == nil ? size : 24)
            .padding(.horizontal, title == nil ? 0 : 9)
            .background(Capsule().fill(prominent ? Theme.signal.opacity(hovering ? 1 : 0.9)
                                       : tint.opacity(hovering ? 0.16 : quiet ? 0 : 0.1)))
            .animation(Theme.snappy, value: hovering)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            onHover?(inside)
        }
        .help(onHover == nil ? help : "")
        .accessibilityLabel(help)
    }
}
