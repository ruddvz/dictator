import AppKit
import Carbon.HIToolbox
import CoreAudio
import SwiftUI
import os

/// Invalidates delayed panel shrinks when a newer animated layout arrives.
struct PillResizeGeneration {
    private var value: UInt64 = 0

    mutating func next() -> UInt64 {
        value &+= 1
        return value
    }

    func matches(_ token: UInt64) -> Bool { value == token }
}

/// Always-on-top dictation indicator at the bottom of the screen. It is a non-activating panel,
/// so clicking it never steals focus from the app that will receive the dictated text.
@MainActor
final class FloatingPillController {
    private var panel: NSPanel?
    private weak var model: AppModel?
    private var contentSize = minimumPanelSize
    /// A smaller size waits for the closing animation, so the panel never clips the pill as it shrinks.
    private var pendingShrink: DispatchWorkItem?
    /// Canceled DispatchWorkItems can still run after they have been enqueued. This generation
    /// makes sure only the most recent geometry measurement is allowed to resize the panel.
    private var resizeGeneration = PillResizeGeneration()
    private var escapeMonitors: [Any] = []
    private var screenObserver: Any?
    private weak var interactiveHosting: PillInteractiveHosting?
    private var lastMeasuredSize: CGSize = .zero
    /// The screen the pill sits on: wherever the pointer was when it appeared or a dictation began.
    private var screen: NSScreen?
    private var wasCapturing = false
    /// Pointer x and pill centre when a drag began.
    private var dragStart: (mouseX: CGFloat, centerX: CGFloat)?
    /// Where along the bottom edge the pill sits, 0…1 of the screen width; remembered.
    private var centerFraction = PillPlacement.storedFraction

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

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
            _ = model.meetingNotes.resultNoteID
            _ = model.meetingNotes.notice
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
        let meetingCardIsUp = model.meetingNotes.resultNoteID != nil || model.meetingNotes.notice != nil
        let cardIsUp = model.showsFloatingPill && (model.showsFinishedTranscript || meetingCardIsUp)
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
                else if model.showsFinishedTranscript { model.dismissFinishedTranscript() }
                // Esc never stops a meeting; it only closes the meeting's cards.
                else if model.meetingNotes.notice != nil { model.meetingNotes.dismissNotice() }
                else { model.meetingNotes.dismissResult() }
            }
            return true
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = dismiss($0) }) {
            escapeMonitors.append(global)
        }
        // Inside HushKey, a Save panel, alert or sheet owns Esc (Export… from the meeting card).
        let localDismiss: (NSEvent) -> NSEvent? = { event in
            if NSApp.modalWindow != nil || NSApp.keyWindow?.isSheet == true || NSApp.keyWindow?.attachedSheet != nil {
                return event
            }
            return dismiss(event) ? nil : event
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: localDismiss) {
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
        hosting.frame = CGRect(origin: .zero, size: contentSize)
        panel.contentView = hosting
        interactiveHosting = hosting
        self.panel = panel
        screen = PillPlacement.screenUnderPointer()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let current = self.screen, !NSScreen.screens.contains(current) {
                            self.screen = PillPlacement.screenUnderPointer()
                        }
                        self.place()
                    }
                }
        }
        resize(to: hosting.fittingSize)
        place()
        panel.orderFrontRegardless()
    }

    private func hide() {
        _ = resizeGeneration.next()
        pendingShrink?.cancel()
        pendingShrink = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        interactiveHosting = nil
    }

    /// Grows at once, before the opening animation is drawn, and shrinks only once the closing
    /// animation has settled. Resizing a window mid-animation clips the pill or makes it flicker.
    private func resize(to measured: CGSize) {
        guard measured.width > 0, measured.height > 0 else { return }
        lastMeasuredSize = measured
        // Never smaller than the recording pill plus its hint, so idle → hover → recording happens
        // inside one window frame. Resizing the window as the pill opened showed the old pill
        // up and to the left for a frame before the new one drew. The extra area is transparent,
        // so clicks there pass through to the app underneath.
        let size = CGSize(width: max(measured.width, Self.minimumPanelSize.width),
                          height: max(measured.height, Self.minimumPanelSize.height))
        let generation = resizeGeneration.next()
        pendingShrink?.cancel()
        pendingShrink = nil
        let grown = CGSize(width: max(size.width, contentSize.width), height: max(size.height, contentSize.height))
        apply(grown)
        updateActiveContentRect(measured: measured, panelSize: grown)
        guard grown != size else { return }
        let shrink = DispatchWorkItem { [weak self] in
            guard let self, self.resizeGeneration.matches(generation) else { return }
            self.apply(size)
            self.updateActiveContentRect(measured: measured, panelSize: size)
            self.pendingShrink = nil
        }
        pendingShrink = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: shrink)
    }

    private func updateActiveContentRect(measured: CGSize, panelSize: CGSize) {
        let width = min(measured.width, panelSize.width)
        let height = min(measured.height, panelSize.height)
        let originX = (panelSize.width - width) / 2
        let originY: CGFloat = 0
        interactiveHosting?.activeContentRect = CGRect(x: originX, y: originY, width: width, height: height)
    }

    /// Fits the recording capsule with × and ✓, the elapsed timer, the hover row with Meeting
    /// notes, and a one-line hint above, plus the 8 pt shadow margin on every side.
    /// Generous enough to host all pill morph states without mid-animation window resizing.
    static let minimumPanelSize = CGSize(width: 360, height: 96)

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
        // Lay out and redraw in the same pass as the move, so the old contents never show at the
        // new frame's corner.
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
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

protocol PillInteractiveHosting: AnyObject {
    var activeContentRect: CGRect { get set }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content>, PillInteractiveHosting {
    var activeContentRect: CGRect = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard activeContentRect.isEmpty || activeContentRect.contains(point) else { return nil }
        return super.hitTest(point) ?? (activeContentRect.contains(point) ? self : nil)
    }
}

struct FloatingPillView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    /// Dragging slides the pill along the bottom edge; `true` when the drag ends.
    var onDrag: (Bool) -> Void = { _ in }
    /// Puts the pill back in the middle of the bottom edge.
    var onCentre: () -> Void = {}
    /// The pill's measured size, so the panel can fit it.
    var onSize: (CGSize) -> Void = { _ in }

    @State private var isHovering = false
    /// After a few quiet seconds the idle bar shrinks to a dot, out of the way.
    @State private var hoveredControl: PillControl?
    @State private var showsDone = false
    @State private var doneToken = 0
    @State private var copied = false
    /// The start is taking longer than a blink: only then name the wait and sweep the ribbon.
    /// A normal start (about 0.3 s) goes straight from the resting line to the live ribbon.
    @State private var isSlowStart = false
    /// The timer joins the pill once a dictation passes 30 s.
    @State private var showsElapsed = false
    /// The pointer is over a notice or the copy card: its countdown waits, as in Wispr Flow.
    @State private var isHoveringCard = false
    /// How long a card that loses nothing by closing stays up on its own.
    static let cancelledCountdown: TimeInterval = 5
    static let finishedCountdown: TimeInterval = 8
    static let slowStartDelay: Duration = .milliseconds(600)

    enum Phase: CaseIterable { case idle, hover, preparing, listening, finishing, error, done,
                               meetingStarting, meeting, meetingSaving }
    /// Renders one fixed phase, for snapshot reviews of the pill's spacing and icons.
    var previewPhase: Phase? = nil
    var previewShowsControls = true
    private enum PillControl { case dictate, cancel, finish, notes, meeting, stopMeeting, cancelMeeting }

    private var isFinishing: Bool { model.isFinalizingDictation || model.transcriber.isFinalizing }

    private var isMeetingPhase: Bool { phase == .meetingStarting || phase == .meeting || phase == .meetingSaving }

    /// The saved meeting to show above the pill, kept out of the way while a dictation runs.
    private var meetingResult: MeetingNote? {
        guard let id = model.meetingNotes.resultNoteID, cardState == .hidden,
              phase == .idle || phase == .hover || phase == .done || phase == .error
        else { return nil }
        return model.meetingNotes.notes.first { $0.id == id }
    }

    private var phase: Phase {
        if let previewPhase { return previewPhase }
        if isFinishing { return .finishing }
        // The microphone buffers while recognition gets ready, so show the live meter at once.
        if model.audio.isRunning { return .listening }
        if model.isStartingDictation { return .preparing }
        // A meeting holds the pill until it is saved: the capture is the most important thing on screen.
        if model.meetingNotes.isStarting { return .meetingStarting }
        if model.meetingNotes.isCapturing { return .meeting }
        if model.meetingNotes.isFinalizing { return .meetingSaving }
        if model.dictationNotice != nil { return .error }
        if showsDone { return .done }
        return isHovering ? .hover : .idle
    }

    /// Hold to talk keeps a hand on the key, so the pill is just the meter; click and
    /// hands-free dictation get cancel and finish controls.
    private var showsControls: Bool {
        if previewPhase != nil { return previewShowsControls && (phase == .listening || phase == .preparing) }
        return (phase == .listening || phase == .preparing) && !model.dictationShortcutHeld
    }

    private var cardState: TranscriptCard.State {
        TranscriptCard.state(isCapturing: model.audio.isRunning || isFinishing, hasTarget: model.dictationHasTarget,
                             transcript: model.transcriber.text, keepsFinishedText: model.showsFinishedTranscript)
    }

    var body: some View {
        VStack(spacing: Theme.s2) {
            if cardState != .hidden {
                transcriptCard
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let note = meetingResult {
                MeetingResultCard(note: note,
                                  isDigesting: model.meetingNotes.digestingNoteID == note.id,
                                  isFallback: model.meetingNotes.fallbackDigestNoteIDs.contains(note.id),
                                  onOpen: { model.openMeetingNote(note.id) },
                                  onCopy: { model.copyMeetingNote(note.id) },
                                  onExport: { model.exportMeetingNote(note.id) },
                                  onClose: { model.meetingNotes.dismissResult() },
                                  isHovering: $isHoveringCard)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
                        .combined(with: .offset(y: 6)))
            } else if let notice = model.meetingNotes.notice, !isMeetingPhase, phase != .error {
                MeetingNoticeCard(message: notice,
                                  onOpen: { model.meetingNotes.dismissNotice(); model.openMeetingNotes() },
                                  onClose: { model.meetingNotes.dismissNotice() },
                                  isHovering: $isHoveringCard)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            if phase == .error, let notice = model.dictationNotice {
                noticeCard(notice)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
                        .combined(with: .offset(y: 6)))
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
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.meetingNotes.resultNoteID)
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: model.meetingNotes.notice)
            .transaction { transaction in
                if reduceMotion {
                    transaction.disablesAnimations = true
                    transaction.animation = nil
                }
            }
            .task(id: phase == .preparing) {
                isSlowStart = false
                guard phase == .preparing else { return }
                try? await Task.sleep(for: Self.slowStartDelay)
                if !Task.isCancelled, phase == .preparing { isSlowStart = true }
            }
            .onChange(of: model.audio.isRunning) { _, running in
                if running { copied = false }
            }
            // Keyed on the observed mic state; the start time itself isn't observed.
            .task(id: model.audio.isRunning) {
                showsElapsed = false
                guard model.audio.isRunning else { return }
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, model.audio.isRunning else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showsElapsed = true }
            }
            .onChange(of: phase) { old, new in
                hoveredControl = nil
                Logger(subsystem: "com.ruddvz.hushkey", category: "start")
                    .notice("pill \(String(describing: old), privacy: .public) -> \(String(describing: new), privacy: .public) hint=\(hint?.title ?? "-", privacy: .public)")
            }
            .onChange(of: model.completedDictationCount) {
                doneToken += 1
                let token = doneToken
                // The pill confirms typing only; nothing was copied when the card is up instead.
                guard model.didInsertCurrentDictation else { showsDone = false; return }
                showsDone = true
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    if token == doneToken { showsDone = false }
                }
            }
    }

    /// The bar, plus the Meeting notes button that slides out beside it on hover. The bar itself
    /// is one capsule that springs between sizes (rest → mic button → recorder), so the
    /// pointer sees it grow rather than swap.
    private var pill: some View {
        let isHover = phase == .hover
        return HStack(spacing: isHover ? 6 : 0) {
            // A matching empty slot on the left keeps the bar centred where it rested, so it grows
            // in place instead of sliding left when Meeting notes appears on its right.
            if isHover {
                Color.clear
                    .frame(width: Metrics.height, height: Metrics.height)
                    .allowsHitTesting(false)
            }
            bar
            if isHover {
                PillIconButton(systemImage: "person.2.fill", help: "Record a meeting", quiet: true,
                               glyphSize: 11, size: Metrics.height,
                               onHover: { hoveredControl = $0 ? .notes : nil }) {
                    model.toggleMeetingFromPill()
                }
                // Same material as the pill beside it, so the two read as one control family.
                .background(Circle().fill(Theme.paper))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.32), radius: 6, y: 2)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity)
                        .combined(with: .offset(x: -14))
                        .animation(.spring(response: 0.38, dampingFraction: 0.74).delay(0.05)),
                    removal: .scale(scale: 0.5, anchor: .leading).combined(with: .opacity)
                        .combined(with: .offset(x: -10))
                        .animation(.easeIn(duration: 0.12))))
            }
        }
        // A generous hover target around the thin resting bar, inside the panel's shadow margin.
        .contentShape(Rectangle().inset(by: -6))
        .onHover { inside in
            isHovering = inside
        }
        .contextMenu { pillMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { // VoiceOver and other assistive presses, which can't miss
            guard phase != .finishing, phase != .error, phase != .meetingSaving else { return }
            if isMeetingPhase { model.toggleMeetingFromPill(); return }
            Task { await model.toggleDictation() }
        }
    }

    private var isResting: Bool { phase == .idle || phase == .error }

    private var pillTargetSize: CGSize {
        switch phase {
        case .idle, .error:
            return Metrics.idle
        case .hover:
            return Metrics.hover
        case .preparing, .listening, .finishing:
            let base = showsControls ? Metrics.recorderWidth : Metrics.meterOnlyWidth
            let timer = phase == .listening && showsElapsed ? Metrics.timerWidth + Metrics.gap : 0
            return CGSize(width: base + timer, height: Self.height)
        case .done:
            return CGSize(width: doneWidth, height: Self.height)
        case .meetingStarting:
            return CGSize(width: Metrics.meetingStartingWidth, height: Self.height)
        case .meeting:
            // The clock has a fixed slot, wider past an hour, so the capsule never jumps mid-meeting.
            let clock = meetingClockWidth
            return CGSize(width: Metrics.meetingStartingWidth + clock + Metrics.gap, height: Self.height)
        case .meetingSaving:
            return CGSize(width: Metrics.meetingSavingWidth, height: Self.height)
        }
    }

    private var bar: some View {
        let isHover = phase == .hover
        return content
            .foregroundStyle(Theme.ink)
            .frame(width: pillTargetSize.width, height: pillTargetSize.height)
            // At rest a faint, see-through bar that fills in as it opens.
            .background(Capsule().fill(isResting ? Theme.paper.opacity(0.6) : Theme.paper))
            // The capsule grows around its contents; clipping reveals them instead of letting them spill.
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(stroke,
                                            lineWidth: isResting ? 1 : 0.5))
            // A faint shadow at rest lifts the bar off light desktops; the hairline does it on dark ones.
            .shadow(color: .black.opacity(isResting ? 0.15 : 0.32), radius: isResting ? 2 : 6, y: isResting ? 1 : 2)
            .scaleEffect(isHover && hoveredControl == .dictate ? 1.05 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hoveredControl)
            .animation(.spring(response: 0.35, dampingFraction: 0.76), value: pillTargetSize)
            .contentShape(Capsule())
            .onHover { inside in
                guard phase == .hover || !inside else { return }
                hoveredControl = inside ? .dictate : (hoveredControl == .dictate ? nil : hoveredControl)
            }
            .onTapGesture { press() }
            .gesture(DragGesture(minimumDistance: 10) // a slightly shaky click should not move it
                .onChanged { _ in onDrag(false) }
                .onEnded { _ in onDrag(true) })
    }

    private func press() {
        // A meeting's capsule opens its live transcript; stopping is the ■ button only.
        if phase == .meeting || phase == .meetingSaving {
            model.openMeetingNotes()
            return
        }
        // Only a resting bar starts dictation from a click. While recording, × and ✓ are the
        // only targets, so a click that just misses × can't finish and type the text instead;
        // an error goes away only through its own controls.
        guard phase == .idle || phase == .hover else { return }
        Task { await model.toggleDictation() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .error:
            // A subtle, calm resting sage bar that smoothly animates open when activated
            Capsule()
                .fill(Theme.signal.opacity(0.6))
                .frame(width: Metrics.idleLine.width, height: Metrics.idleLine.height)
                .transition(.opacity.animation(.easeOut(duration: 0.15)))
        case .hover:
            // The mic grows in once the capsule has mostly opened, so nothing is drawn squashed.
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.signal)
                .frame(width: Metrics.hover.width, height: Metrics.hover.height)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7)),
                    removal: .opacity.animation(.easeOut(duration: 0.08))))
                .accessibilityLabel("Start dictation")
        case .preparing, .listening, .finishing:
            recorder
        case .meetingStarting, .meeting, .meetingSaving:
            meetingRecorder
        case .done:
            // Only shown when the words went in: the card above is the feedback otherwise.
            TypedConfirmation(verb: model.insertion.lastDeliveryVerified ? "Typed" : "Pasted",
                              appName: Self.shownAppName(model.typedIntoAppName) ?? (previewPhase == nil ? nil : "Notes"),
                              settled: previewPhase != nil)
                .frame(height: Self.height)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }

    /// App names are cut to fit the pill; HushKey itself is never named.
    private static func shownAppName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != "HushKey" else { return nil }
        return name.count > 18 ? String(name.prefix(17)) + "…" : name
    }

    /// Width of the Typed confirmation: tick, "Typed", "into <App>", and the side padding.
    private var doneWidth: CGFloat {
        let bold = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let regular = NSFont.systemFont(ofSize: 12, weight: .medium)
        let verb = model.insertion.lastDeliveryVerified ? "Typed" : "Pasted"
        var width = 12 + 14 + 6 + (verb as NSString).size(withAttributes: [.font: bold]).width + 12
        if let app = Self.shownAppName(model.typedIntoAppName) ?? (previewPhase == nil ? nil : "Notes") {
            width += 4 + ("into \(app)" as NSString).size(withAttributes: [.font: regular]).width
        }
        return ceil(width)
    }

    /// The pill's geometry, on a 4 pt grid. Controls sit concentric inside the capsule: a 20 pt
    /// circle in a 28 pt capsule leaves the same 4 pt on every side, so the curves run parallel.
    enum Metrics {
        static let height: CGFloat = 28
        static let control: CGFloat = 20
        static let inset: CGFloat = (height - control) / 2
        static let gap: CGFloat = 8
        static let idle = CGSize(width: 44, height: 14)
        static let idleLine = CGSize(width: 18, height: 2.5)
        static let hover = CGSize(width: 60, height: height)
        /// × · ribbon · ✓, and the ribbon alone while the shortcut is held.
        static let recorderWidth = inset + control + gap + ribbonSize.width + gap + control + inset
        static let meterOnlyWidth = ribbonSize.width + 2 * Theme.s3
        static let timerWidth: CGFloat = 30
        /// Meeting glyph · ribbon · ×, and glyph · ribbon while the meeting saves. Recording adds
        /// the clock's slot before ■.
        static let meetingStartingWidth = inset + control + gap + ribbonSize.width + gap + control + inset
        static let meetingSavingWidth = inset + control + gap + ribbonSize.width + Theme.s3
        static let meetingClockWidth: CGFloat = 34
        static let meetingLongClockWidth: CGFloat = 48
    }

    private var meetingClockWidth: CGFloat {
        model.meetingNotes.activeDuration >= 3600 ? Metrics.meetingLongClockWidth : Metrics.meetingClockWidth
    }
    private static let height = Metrics.height
    /// The recording meter: `BreathRibbon`, sized per docs/DESIGN_SYSTEM.md.
    static let ribbonSize = CGSize(width: 58, height: 18)

    /// One capsule from the first press to the typed text: the meter waits, listens, then works,
    /// so the pill never jumps between shapes mid-dictation.
    private var recorder: some View {
        HStack(spacing: Metrics.gap) {
            if showsControls {
                PillIconButton(systemImage: "xmark",
                               help: phase == .preparing ? "Cancel before the microphone starts" : "Cancel without typing",
                               solid: true, size: Metrics.control,
                               onHover: { hoveredControl = $0 ? .cancel : nil }) {
                    model.cancelDictation(offersUndo: true)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            // The same breath ribbon as the hub, the hero and the app icon: one wave everywhere.
            let ribbonMode: BreathRibbon.Mode = switch phase {
            case .listening: .live
            case .preparing: isSlowStart ? .waiting : .rest
            default: .working
            }
            LiveLevel(model.audio) { BreathRibbon(level: $0, mode: ribbonMode, tint: Theme.ink) }
                .frame(width: Self.ribbonSize.width, height: Self.ribbonSize.height)
            if phase == .listening, showsElapsed { elapsed }
            if showsControls {
                PillIconButton(systemImage: "checkmark", help: "Finish and type it", prominent: true,
                               disabled: phase == .preparing, size: Metrics.control,
                               onHover: { hoveredControl = $0 ? .finish : nil }) {
                    Task { await model.toggleDictation() }
                }
                .disabled(phase == .preparing)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .padding(.horizontal, showsControls ? Metrics.inset : 12)
        .frame(height: Self.height)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))

    }

    /// A meeting on the pill: the meeting glyph, the same breath ribbon as dictation (it waits,
    /// listens, then works), the running clock, and one sage ■ to stop and save. Clicking the
    /// capsule opens the live transcript; Esc and stray clicks never end a meeting.
    private var meetingRecorder: some View {
        let meeting = model.meetingNotes
        let mode: BreathRibbon.Mode = switch phase {
        case .meeting: .live
        case .meetingStarting: .waiting
        default: .working
        }
        return HStack(spacing: Metrics.gap) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.signal)
                .frame(width: Metrics.control, height: Metrics.control)
            MeetingLevel(meeting: meeting) { level in
                BreathRibbon(level: phase == .meeting ? level : 0, mode: mode, tint: Theme.ink)
            }
            .frame(width: Self.ribbonSize.width, height: Self.ribbonSize.height)
            if phase == .meeting {
                MeetingClock(startedAt: meeting.activeMeetingStartedAt)
                    .frame(width: meetingClockWidth)
                PillIconButton(systemImage: "stop.fill", help: "Stop and save the meeting", prominent: true,
                               size: Metrics.control,
                               onHover: { hoveredControl = $0 ? .stopMeeting : nil }) {
                    meeting.stop()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            } else if phase == .meetingStarting {
                PillIconButton(systemImage: "xmark", help: "Cancel the meeting", solid: true, size: Metrics.control,
                               onHover: { hoveredControl = $0 ? .cancelMeeting : nil }) {
                    meeting.cancelStarting()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .padding(.leading, Metrics.inset)
        .padding(.trailing, phase == .meetingSaving ? 12 : Metrics.inset)
        .frame(height: Self.height)
        .contentShape(Capsule())
        .onHover { inside in
            guard phase == .meeting else { return }
            if inside { if hoveredControl == nil { hoveredControl = .meeting } }
            else if hoveredControl == .meeting { hoveredControl = nil }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    static func sourceLabel(_ source: MeetingAudioSource) -> String {
        switch source {
        case .microphone: "Mic"
        case .systemAudio: "Mac audio"
        case .both: "Mic + Mac audio"
        }
    }

    /// Short tooltip above the pill: what a hovered control does and its key, or what the pill
    /// is waiting for. Shown at once, unlike a system tooltip in a non-activating panel.
    private var hint: PillHint.Content? {
        switch hoveredControl {
        case .dictate?: return .init(title: "Dictate", shortcut: model.dictationShortcut.label)
        case .cancel?: return .init(title: "Cancel", shortcut: "esc")
        case .finish?: return .init(title: "Finish", shortcut: model.dictationShortcut.label)
        case .notes?: return .init(title: "Record meeting from \(Self.sourceLabel(model.meetingNotes.audioSource))", shortcut: nil)
        case .meeting?: return .init(title: "Open live transcript", shortcut: nil)
        case .stopMeeting?: return .init(title: "Stop and save", shortcut: nil)
        case .cancelMeeting?: return .init(title: "Cancel", shortcut: nil)
        case nil: break
        }
        switch phase {
        // Over the bar but between its buttons: still say what it does.
        case .hover: return .init(title: "Dictate", shortcut: model.dictationShortcut.label)
        case .preparing:
            if model.audio.isAwaitingPermission || model.transcriber.isAwaitingPermission {
                return .init(title: "Allow access in the dialog", shortcut: nil)
            }
            guard isSlowStart else { return nil }
            return .init(title: model.audio.isStarting ? "Waiting for microphone…" : "Getting ready…", shortcut: nil)
        case .meetingStarting:
            let meeting = model.meetingNotes
            if meeting.audio.isAwaitingPermission || meeting.transcriber.isAwaitingPermission {
                return .init(title: "Allow access in the dialog", shortcut: nil)
            }
            return .init(title: "Starting meeting…", shortcut: nil)
        case .meetingSaving: return .init(title: "Saving meeting…", shortcut: nil)
        default: return nil
        }
    }

    /// With no text field to type into, or when typing failed, the words stay up after
    /// finishing with Copy and close.
    private var transcriptCard: some View {
        let hint: String? = if case .finished(let value) = cardState { value } else { nil }
        let shownHint = model.insertion.isEnabled ? hint : "Typing into apps is off"
        let isSuccess = model.didInsertCurrentDictation
        return VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                if isSuccess {
                    StateIcon(phase: .done)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.signal)
                } else {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.signal)
                }
                if let shownHint {
                    Text(shownHint)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.s2)
                // Finished text is already in History, so the card can close itself; hovering waits.
                CountdownCloseButton(duration: Self.finishedCountdown,
                                     paused: isHoveringCard, size: 22, help: "Close (Esc)") {
                    model.dismissFinishedTranscript()
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                Text(model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 110)
            .contentTransition(.opacity)
            HStack(spacing: Theme.s2) {
                if !model.insertion.isEnabled {
                    Button("Turn on typing") {
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
                    if copied {
                        Text("Copied")
                    } else {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.signal, foreground: Theme.paper))
                .keyboardShortcut("c", modifiers: .command)
                .help("Copy to the clipboard (⌘C)")
            }
        }
        .padding(Theme.s3)
        .frame(width: 320)
        .onHover { isHoveringCard = $0 }
        .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous).fill(Theme.paper))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Finished transcript")
    }

    /// What went wrong, as a card above the pill (after Wispr Flow's notices): icon and title,
    /// a round close button, one or two lines of detail, then its actions at the bottom right.
    /// Always dark, like the home hero, so it reads on any desktop.
    private func noticeCard(_ notice: DictationNotice) -> some View {
        let symbol = if notice.isReview { "eye" } else if notice.kind == .cancelled {
            "arrow.uturn.backward.circle"
        } else {
            "exclamationmark.triangle"
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(notice.isNeutral ? Theme.ink : Theme.danger)
                    .frame(width: 18)
                Text(notice.message)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.s2)
                // Only the cancelled notice closes itself: dismissing an error drops the audio kept
                // for Retry, so those wait for you.
                CountdownCloseButton(duration: notice.kind == .cancelled ? Self.cancelledCountdown : nil,
                                     paused: isHoveringCard, help: "Dismiss") {
                    model.dismissDictationNotice()
                }
                .id(notice.message + notice.detail)
            }
            if !notice.detail.isEmpty {
                Text(notice.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
            }
            HStack(spacing: Theme.s2) {
                Spacer(minLength: 0)
                noticeActions(notice)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.top, 14)
        .padding(.bottom, Theme.s4)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous).fill(Theme.heroBase))
        .overlay(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous).strokeBorder(Theme.ink.opacity(0.08), lineWidth: Theme.hairlineWidth))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .onHover { isHoveringCard = $0 }
        // Dark in both modes, so the shared tokens resolve to their dark values here.
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    /// The notice's actions; the most useful one is filled, the rest are outlined.
    @ViewBuilder
    private func noticeActions(_ notice: DictationNotice) -> some View {
        if notice.offersMicrophoneHelp {
            Menu {
                microphoneChoices
            } label: {
                Text("Microphone")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .buttonStyle(NoticeButtonStyle(prominent: false))
            .help("Choose the microphone")
            Button("Sound settings") { model.openSoundInputSettings() }
                .buttonStyle(NoticeButtonStyle(prominent: false))
        }
        if notice.canPasteAgain {
            Button("Paste again") { Task { await model.pasteLastDictationAgain() } }
                .buttonStyle(NoticeButtonStyle(prominent: !notice.canRetry && notice.missingPermission == nil))
                .help(notice.message == "Check the field first"
                      ? "It may already be there. Paste again only if it’s missing."
                      : "Type it again only if \(model.capturedInsertionTargetName ?? "the original app") still has focus.")
        }
        if notice.kind == .cancelled {
            Button("Undo") { Task { await model.retryDictation() } }
                .buttonStyle(NoticeButtonStyle(prominent: true))
                .help("Transcribe what you said and type it")
        } else if notice.canRetry {
            Button("Retry") { Task { await model.retryDictation() } }
                .buttonStyle(NoticeButtonStyle(prominent: notice.missingPermission == nil))
                .help("Transcribe the last recording again")
        }
        if let privacy = notice.missingPermission {
            Button("Open Settings") {
                model.openPrivacySettings(privacy)
                model.dismissDictationNotice()
            }
            .buttonStyle(NoticeButtonStyle(prominent: true))
        }
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
        .disabled(model.audio.isRunning || model.audio.isStarting)
        .help("Stop recording before changing microphones.")
    }

    /// Right-click menu: microphone, sounds, and getting back to HushKey.
    @ViewBuilder
    private var pillMenu: some View {
        microphoneChoices
        Toggle("Dictation Sounds", isOn: Binding(get: { model.playsDictationSounds },
                                                       set: { model.playsDictationSounds = $0 }))
        Divider()
        Button("Move to Center") { onCentre() }
        if model.meetingNotes.isCapturing || model.meetingNotes.isStarting {
            Button(model.meetingNotes.isStarting ? "Cancel Meeting Start" : "Stop Meeting and Save") {
                model.meetingNotes.stop()
            }
        } else {
            Button("Record Meeting") { model.startMeeting() }
                .disabled(model.meetingNotes.isFinalizing)
        }
        Picker("Meeting Audio", selection: Binding(get: { model.meetingNotes.audioSource },
                                                   set: { model.meetingNotes.audioSource = $0 })) {
            ForEach(MeetingAudioSource.allCases) { Text($0.rawValue).tag($0) }
        }
        .disabled(model.meetingNotes.isCapturing || model.meetingNotes.isStarting)
        Button("Open Meeting Notes") { model.openMeetingNotes() }
        Button("Open HushKey") {
            model.screen = .dictation
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Hide for 1 Hour") { model.hideFloatingPill(for: 3600) }
        Button("Hide Dictation Bar") { model.showsFloatingPill = false }
    }

    private var stroke: Color {
        switch phase {
        case .idle, .error: Theme.ink.opacity(0.22)
        default: Theme.ink.opacity(0.12)
        }
    }

    /// Elapsed time, only once a dictation runs long enough for it to help.
    /// Shown from 30 s on, in a fixed-width slot so the pill grows once instead of every second.
    private var elapsed: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(model.dictationStartedAt ?? context.date)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.ink2)
                .frame(width: Metrics.timerWidth, alignment: .trailing)
        }
        .transition(.opacity)
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle, .hover: "Start dictation"
        case .preparing: "Preparing local speech recognition. Cancel dictation startup"
        case .listening: model.dictationShortcutHeld ? "Listening. Release \(model.dictationShortcut.label) to finish" : "Listening. Stop dictation"
        case .finishing: "Transcribing"
        case .error:
            model.dictationNotice?.isReview == true
                ? "Transcript saved for review before typing. \(model.dictationNotice?.detail ?? "")"
                : model.dictationNotice?.kind == .cancelled
                    ? "Dictation cancelled. \(model.dictationNotice?.detail ?? "")"
                    : "Dictation problem: \(model.dictationNotice?.message ?? ""). \(model.dictationNotice?.detail ?? "")"
        case .done: "Dictation finished"
        case .meetingStarting: "Starting meeting capture. Cancel"
        case .meeting: "Recording meeting from \(Self.sourceLabel(model.meetingNotes.activeAudioSource ?? model.meetingNotes.audioSource)). Stop and save"
        case .meetingSaving: "Saving the meeting"
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.ink)
            if let shortcut { PillKey(label: shortcut) }
        }
        .padding(.leading, 9)
        .padding(.trailing, shortcut == nil ? 9 : 3)
        .frame(height: 22)
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
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.s1)
            .frame(minWidth: 16, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: Theme.r4, style: .continuous).fill(Theme.keycap))
            .overlay(RoundedRectangle(cornerRadius: Theme.r4, style: .continuous).strokeBorder(Theme.keycapEdge, lineWidth: 0.5))
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
    /// A filled grey circle that stands on its own, off the pill or beside the meter.
    var solid = false
    /// Drawn neutral, not as a faded accent, while it can't be pressed yet.
    var disabled = false
    /// Glyph point size; by default about half the circle, so × and ✓ read at the same weight.
    var glyphSize: CGFloat? = nil
    var size: CGFloat = 20
    /// Reports hover to the pill, which shows its own hint instead of a slow system tooltip.
    var onHover: ((Bool) -> Void)? = nil
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.s1) {
                Image(systemName: systemImage)
                    .font(.system(size: glyphSize ?? (quiet ? 11 : (size * 0.45).rounded()), weight: quiet || glyphSize != nil ? .semibold : .bold))
                if let title {
                    Text(title).font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(disabled ? tint.opacity(0.3)
                             : prominent ? Theme.paper : tint.opacity(hovering || solid ? 0.95 : 0.7))
            .frame(minWidth: title == nil ? size : 24, minHeight: title == nil ? size : 24)
            .padding(.horizontal, title == nil ? 0 : 9)
            .background(Capsule().fill(disabled ? tint.opacity(0.1)
                                       : prominent ? Theme.signal.opacity(hovering ? 1 : 0.9)
                                       : tint.opacity(hovering ? (solid ? 0.3 : 0.16) : quiet ? 0 : solid ? 0.2 : 0.1)))
            .background(Capsule().fill(solid ? Theme.paper : .clear))
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

/// A capsule action on the dark notice card: filled for the main action, outlined otherwise.
private struct NoticeButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Theme.heroBase : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(prominent ? Theme.ink : Color.clear))
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(prominent ? 0 : 0.28), lineWidth: Theme.hairlineWidth))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A round close button whose ring drains while the card counts down, then closes it, after
/// Wispr Flow's notices. Hovering the card (`paused`) refills it and holds it open. With no
/// duration it is a plain ring and the card stays until it is closed.
struct CountdownCloseButton: View {
    var duration: TimeInterval?
    var paused = false
    var size: CGFloat = 26
    var help: String
    var action: () -> Void

    @State private var startedAt = Date()
    @State private var fired = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Theme.ink.opacity(0.22), lineWidth: 1.5)
                if let duration {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
                        let left = paused ? 1 : max(0, 1 - context.date.timeIntervalSince(startedAt) / duration)
                        Circle()
                            .inset(by: 0.75)
                            .trim(from: 0, to: left)
                            .stroke(Theme.ink.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .onChange(of: left <= 0) { _, done in
                                guard done, !fired else { return }
                                fired = true
                                action()
                            }
                    }
                }
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        // Leaving the card starts the count again from full, so a glance never loses the card.
        .onChange(of: paused) { _, isPaused in if !isPaused { startedAt = Date() } }
    }
}

/// "✓ Typed into Notes" (or "Pasted" when unverified): the working wave folds into the tick, then the words fade in after it.
private struct TypedConfirmation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// "Typed" when HushKey read the words back from the field, "Pasted" when it couldn't check.
    let verb: String
    let appName: String?
    var settled = false
    @State private var icon: StateIcon.Phase = .working
    @State private var showsText = false
    @State private var tickScale: CGFloat = 0.8

    var body: some View {
        HStack(spacing: 6) {
            StateIcon(phase: settled ? .done : icon)
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.signal)
                .scaleEffect(settled ? 1 : tickScale)
            HStack(spacing: Theme.s1) {
                // One weight and one colour: no bold-plus-dim split.
                Text(appName.map { "\(verb) into \($0)" } ?? verb)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            .lineLimit(1)
            .fixedSize()
            .opacity(settled || showsText ? 1 : 0)
            .offset(x: settled || showsText ? 0 : -4)
        }
        .padding(.horizontal, Theme.s3)
        .onAppear {
            guard !reduceMotion else { icon = .done; showsText = true; tickScale = 1; return }
            icon = .done
            // The check settles with a small overshoot as the stroke lands, then the words follow.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55).delay(0.05)) { tickScale = 1 }
            withAnimation(.easeOut(duration: 0.22).delay(0.14)) { showsText = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appName.map { "\(verb) into \($0)" } ?? verb)
    }
}
