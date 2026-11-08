import AppKit
import AVFoundation
import SwiftUI

/// HushKey's 60-second first run, as a sheet over the hub: permissions, a mic test drawn with the
/// breath ribbon, the shortcut as live keycaps, one practice dictation that shows cleanup working,
/// and a closing whisper. No account. Every step can be skipped, and so can the whole tour.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flow = OnboardingFlow()
    /// Moving forward, the next step rises from the right; going back, from the left.
    @State private var movingForward = true
    /// The loudest level the mic test heard, to compare the whisper with.
    @State private var speakingPeak: Float = 0
    private let record = OnboardingRecord()

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                stepView(flow.step)
                    .id(flow.step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Theme.s6)
            .clipped()
            footer
        }
        .frame(width: Theme.onboardingSize.width, height: Theme.onboardingSize.height)
        .background(Theme.sheet)
        .foregroundStyle(Theme.ink)
        .font(.hkBody)
        .tint(Theme.ink)
        .animation(reduceMotion ? nil : Theme.glide, value: flow.step)
        .onAppear { syncPracticeCapture() }
        .onChange(of: flow.step) { _, step in
            syncPracticeCapture()
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                 userInfo: [.announcement: step.title, .priority: NSNumber(value: 50)])
        }
        .onDisappear {
            model.practiceKeepsDictationInApp = false
            // Closed any other way than Finish (Esc, Skip setup, the window closing) counts as skipped.
            if !flow.isFinished { record.record(.skipped) }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: Theme.s3) {
            HStack(spacing: Theme.figureGap) {
                ForEach(OnboardingStep.allCases) { step in
                    let reached = step.rawValue <= flow.index
                    Button {
                        go(to: step)
                    } label: {
                        Capsule()
                            .fill(step == flow.step || flow.completed.contains(step) ? Theme.signal
                                  : reached ? Theme.ink3 : Theme.hairline)
                            .frame(width: step == flow.step ? Theme.s5 : Theme.dot, height: Theme.dot)
                            .contentShape(Rectangle().inset(by: -4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!(reached || flow.completed.contains(step)))
                    .accessibilityLabel("\(step.shortName), step \(step.rawValue + 1) of \(flow.count)")
                    .accessibilityAddTraits(step == flow.step ? .isSelected : [])
                }
            }
            .animation(Theme.snappy, value: flow.step)
            Text("Step \(flow.index + 1) of \(flow.count)")
                .font(.hkMeta.monospacedDigit())
                .foregroundStyle(Theme.ink3)
                .contentTransition(.numericText(value: Double(flow.index)))
            Spacer()
            Button("Skip setup") { skipAll() }
                .buttonStyle(.plain)
                .font(.hkCaption)
                .foregroundStyle(Theme.ink2)
                .keyboardShortcut(.cancelAction)
                .help("Close the tour. Reopen it any time from Help → HushKey Setup Tour.")
        }
        .padding(.horizontal, Theme.s6)
        .padding(.top, Theme.s5)
        .padding(.bottom, Theme.s4)
    }

    private var footer: some View {
        HStack(spacing: Theme.s2) {
            if !flow.isFirst {
                Button("Back") { move { flow.back() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Spacer()
            if flow.currentStepPassed {
                Button(flow.continueTitle, icon: flow.isLast ? .check : .arrowRight) { next() }
                    .buttonStyle(PrimaryButtonStyle())
                    .transition(.opacity)
            } else {
                Button(flow.continueTitle) { next() }
                    .buttonStyle(SecondaryButtonStyle())
                    .transition(.opacity)
            }
        }
        .animation(Theme.snappy, value: flow.currentStepPassed)
        .padding(.horizontal, Theme.s6)
        .padding(.vertical, Theme.s4)
        .overlay(alignment: .top) { RowDivider() }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let rise: CGFloat = movingForward ? 24 : -24
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: rise)),
                           removal: .opacity.animation(.easeOut(duration: 0.1)))
    }

    @ViewBuilder
    private func stepView(_ step: OnboardingStep) -> some View {
        let passed: () -> Void = { if !flow.completed.contains(step) { flow.markPassed(step) } }
        switch step {
        case .permissions: PermissionsStep(passed: passed)
        case .micTest: MicTestStep(speakingPeak: $speakingPeak, passed: passed)
        case .shortcut: ShortcutStep(passed: passed)
        case .practice: PracticeStep(passed: passed)
        case .whisper: WhisperStep(speakingPeak: speakingPeak, passed: passed)
        }
    }

    // MARK: Moving

    private func move(forward: Bool = false, _ change: () -> Void) {
        movingForward = forward
        change()
    }

    private func go(to step: OnboardingStep) {
        move(forward: step.rawValue > flow.index) { flow.go(to: step) }
    }

    private func next() {
        move(forward: true) { flow.advance() }
        if flow.isFinished {
            record.record(.completed)
            finish()
        }
    }

    private func skipAll() {
        record.record(.skipped)
        finish()
    }

    private func finish() {
        model.practiceKeepsDictationInApp = false
        model.showsOnboarding = false
        dismiss()
    }

    /// The practice and whisper steps keep their dictations in the app, for their fields.
    private func syncPracticeCapture() {
        model.practiceKeepsDictationInApp = [.practice, .whisper].contains(flow.step)
    }
}

// MARK: - Shared pieces

private struct StepHeading: View {
    var step: OnboardingStep
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text(step.title).font(.hkTitle1)
            Text(subtitle)
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, Theme.s5)
        .reveal(0)
    }
}

/// A short status line with a sage check once something worked.
private struct PassedLine: View {
    var text: String

    var body: some View {
        HStack(spacing: Theme.s2) {
            Glyph(.checkCircle, size: Theme.iconM).foregroundStyle(Theme.signal)
            Text(text).font(.hkCallout)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
        .accessibilityElement(children: .combine)
    }
}

/// The voice, drawn as HushKey's one voice form: resting, live with the level, or working.
private struct VoiceRibbon: View {
    var level: Float
    var mode: BreathRibbon.Mode
    var height: CGFloat = 72

    var body: some View {
        BreathRibbon(level: level, mode: mode, tint: Theme.signal)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.s3)
            .padding(.horizontal, Theme.s5)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The dictation key, spelled out for the step copy.
@MainActor private func shortcutPhrase(_ model: AppModel) -> String {
    model.dictationShortcut.usesFunctionKey ? "fn" : model.dictationShortcut.label
}

// MARK: - 1 Permissions

private struct PermissionsStep: View {
    @Environment(AppModel.self) private var model
    var passed: () -> Void
    @State private var statuses: [OnboardingPermission: OnboardingPermission.Status] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(step: .permissions,
                        subtitle: "HushKey needs two macOS permissions. There's no account, and nothing leaves this Mac.")
            VStack(spacing: Theme.s3) {
                ForEach(Array(OnboardingPermission.allCases.enumerated()), id: \.element) { order, permission in
                    PermissionCard(permission: permission, status: statuses[permission] ?? .notAsked) {
                        perform(permission)
                    }
                    .reveal(order + 1)
                }
            }
            if OnboardingPermission.allGranted(statuses) {
                PassedLine(text: "Both are on.")
                    .padding(.top, Theme.s4)
            }
        }
        .animation(Theme.gentle, value: statuses)
        // Accessibility has no change notification, so check once a second while this step shows.
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() {
        let microphone: OnboardingPermission.Status = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .off
        }
        let trusted = AXIsProcessTrusted()
        let wasTrusted = statuses[.accessibility] == .granted
        let next: [OnboardingPermission: OnboardingPermission.Status] = [
            .microphone: microphone,
            // Untrusted can't be told apart from never asked, so it reads neutral, not red.
            .accessibility: trusted ? .granted : .notAsked,
        ]
        if next != statuses { statuses = next }
        // fn monitors added before access was granted stay deaf until they're added again.
        if trusted, !wasTrusted { model.refreshFunctionKeyStatus() }
        if OnboardingPermission.allGranted(next) { passed() }
    }

    private func perform(_ permission: OnboardingPermission) {
        switch permission.action(for: statuses[permission] ?? .notAsked) {
        case .request:
            Task { @MainActor in
                let outcome = await LocalPermissionAccess.microphone()
                refresh()
                if outcome == .denied || outcome == .restricted { NSWorkspace.shared.open(permission.settingsURL) }
            }
        case .openSettings:
            NSWorkspace.shared.open(permission.settingsURL)
        case nil:
            break
        }
    }
}

private struct PermissionCard: View {
    var permission: OnboardingPermission
    var status: OnboardingPermission.Status
    var perform: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s4) {
            // The glyph alone, sage once granted: no circle tile behind it.
            Glyph(permission == .microphone ? .mic : .keyboard, size: Theme.iconL)
                .foregroundStyle(status == .granted ? Theme.signal : Theme.ink2)
                .frame(width: Theme.iconXL, height: Theme.iconXL)
            VStack(alignment: .leading, spacing: Theme.s0) {
                Text(permission.title).font(.hkHeadline)
                Text(permission.reason)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.s1) {
                    Circle()
                        .fill(status == .granted ? Theme.signal : status == .off ? Theme.danger : Theme.ink3)
                        .frame(width: Theme.dot, height: Theme.dot)
                    Text(permission.statusLine(for: status))
                        .font(.hkMeta)
                        .foregroundStyle(status == .off ? Theme.danger : Theme.ink3)
                        .contentTransition(.opacity)
                }
                .padding(.top, Theme.s0)
            }
            Spacer(minLength: Theme.s3)
            if let title = permission.buttonTitle(for: status) {
                Button(title, action: perform)
                    .buttonStyle(PrimaryButtonStyle())
                    .transition(.opacity)
            } else {
                Glyph(.check, size: Theme.iconL)
                    .foregroundStyle(Theme.signal)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    .accessibilityLabel("On")
            }
        }
        .card(padding: Theme.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(permission.title): \(permission.statusLine(for: status))")
    }
}

// MARK: - 2 Mic test

private struct MicTestStep: View {
    @Environment(AppModel.self) private var model
    @Binding var speakingPeak: Float
    var passed: () -> Void
    /// Its own meter, separate from dictation, so the test never records or transcribes.
    @State private var meter = AudioService()
    @State private var check = MicCheck()
    @State private var micAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(step: .micTest,
                        subtitle: "Say anything at your normal volume. The ribbon follows your voice. Nothing is recorded.")
            VoiceRibbon(level: meter.level, mode: meter.isRunning ? .live : meter.isStarting ? .waiting : .rest)
                .reveal(1)
            HStack(spacing: Theme.s2) {
                Glyph(.mic, size: Theme.iconS).foregroundStyle(Theme.ink3)
                Text(meter.activeDeviceName ?? (micAllowed ? "Starting the microphone…" : "The microphone is off"))
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Button("Sound settings") { model.openSoundInputSettings() }
                    .buttonStyle(.plain)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.top, Theme.s3)
            .reveal(2)

            Group {
                if check.heardVoice {
                    PassedLine(text: "HushKey can hear you.")
                } else if !micAllowed {
                    Text("Turn on the microphone in the first step to try this.")
                        .font(.hkCallout).foregroundStyle(Theme.ink2)
                } else if let error = meter.error {
                    Text(error).font(.hkCallout).foregroundStyle(Theme.danger)
                } else if meter.isRunning, check.peak < 0.02 {
                    Text("Nothing yet. If you're talking, check the input in Sound settings.")
                        .font(.hkCallout).foregroundStyle(Theme.ink3)
                }
            }
            .padding(.top, Theme.s4)
        }
        .animation(Theme.gentle, value: check.heardVoice)
        .onAppear(perform: startMeter)
        .onDisappear { meter.stop() }
        .onChange(of: meter.level) { _, level in
            check.ingest(level)
            if check.heardVoice {
                speakingPeak = max(speakingPeak, check.peak)
                passed()
            }
        }
    }

    private func startMeter() {
        micAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        // Never ask for the microphone from here, and never fight a dictation or meeting for it.
        guard micAllowed, model.captureGate.owner == nil, !model.audio.isRunning else { return }
        meter.selectedDeviceID = model.audio.selectedDeviceID
        Task { await meter.start() }
    }
}

// MARK: - 3 Shortcut

private struct ShortcutStep: View {
    @Environment(AppModel.self) private var model
    var passed: () -> Void
    @State private var lit: Set<String> = []
    @State private var pressedOnce = false
    @State private var monitor: Any?

    var body: some View {
        let keycaps = ShortcutKeycaps(model.dictationShortcut)
        let heldByModel = model.dictationShortcutHeld || model.audio.isRunning
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(step: .shortcut, subtitle: instructions)
            HStack(spacing: Theme.s3) {
                ForEach(keycaps.caps) { cap in
                    LiveKeycap(glyph: cap.glyph, lit: heldByModel || lit.contains(cap.glyph))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.s6)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .reveal(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dictation shortcut \(model.dictationShortcut.label)")
            .accessibilityValue(pressedOnce ? "Pressed" : "Not pressed yet")

            Group {
                if model.dictationShortcutNeedsAttention {
                    Text(model.dictationShortcutStatus)
                        .font(.hkCallout).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if pressedOnce {
                    PassedLine(text: "That's the one. It works from any app.")
                } else {
                    Text("Press it now to see it light up.")
                        .font(.hkCallout).foregroundStyle(Theme.ink3)
                }
            }
            .padding(.top, Theme.s4)
            Text("You can change it later in Settings → Shortcuts.")
                .font(.hkCaption).foregroundStyle(Theme.ink3)
                .padding(.top, Theme.s2)
        }
        .animation(Theme.gentle, value: pressedOnce)
        .onAppear { install(keycaps) }
        .onDisappear(perform: uninstall)
        .onChange(of: heldByModel) { _, held in if held { pressed() } }
    }

    private var instructions: String {
        let key = shortcutPhrase(model)
        if model.dictationShortcut.usesFunctionKey {
            return "Hold fn (the Globe key) and talk; let go and your words are typed. Double-press fn to talk hands-free."
        }
        return model.dictationCaptureBehavior == .hold
            ? "Hold \(key) and talk; let go and your words are typed."
            : "Press \(key) to start talking, and again to stop."
    }

    /// Watches keys only while this window is in front; nothing is recorded or kept.
    private func install(_ keycaps: ShortcutKeycaps) {
        uninstall()
        let keyCode = keycaps.keyCode
        var keyDown = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { event in
            switch event.type {
            case .keyDown where keyCode != nil && event.keyCode == keyCode: keyDown = true
            case .keyUp where keyCode != nil && event.keyCode == keyCode: keyDown = false
            default: break
            }
            let now = keycaps.lit(flags: event.modifierFlags, keyDown: keyDown)
            if now != lit { lit = now }
            if keycaps.isComplete(now) { pressed() }
            return event
        }
    }

    private func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func pressed() {
        guard !pressedOnce else { return }
        pressedOnce = true
        passed()
    }
}

/// A large keycap that sinks and turns sage while held.
private struct LiveKeycap: View {
    var glyph: String
    var lit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: glyph == "fn" ? .leading : .center, spacing: Theme.figureGap) {
            if glyph == "fn" {
                Glyph(.globe, size: Theme.iconM)
                Text("fn").font(.system(size: 20, weight: .semibold, design: .rounded))
            } else {
                Text(glyph).font(.system(size: 30, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(lit ? Theme.inverseInk : Theme.ink)
        .frame(minWidth: glyph.count > 1 || glyph == "↩" ? 96 : 72, minHeight: 72)
        .padding(.horizontal, glyph.count > 2 ? Theme.s3 : 0)
        .background {
            ZStack {
                shape.fill(lit ? Theme.signal : Theme.keycapEdge).offset(y: lit ? 1 : 4)
                shape.fill(lit ? Theme.signal : Theme.keycap)
            }
        }
        .overlay(shape.strokeBorder(lit ? Theme.signal : Theme.keycapEdge, lineWidth: Theme.hairlineWidth))
        .offset(y: lit && !reduceMotion ? 3 : 0)
        .animation(.easeOut(duration: 0.08), value: lit)
    }
}

// MARK: - 4 Practice

private struct PracticeStep: View {
    @Environment(AppModel.self) private var model
    var passed: () -> Void
    @State private var fieldText = ""
    @State private var spoken = ""
    @State private var cleaned = ""
    @State private var isExample = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(step: .practice,
                        subtitle: "Click the field, hold \(shortcutPhrase(model)) and say the line below, slips and all. HushKey keeps what you meant.")
            Text("“\(CleanupPreview.practicePhrase)”")
                .font(.hkTitle3)
                .padding(.bottom, Theme.s3)
                .reveal(1)

            VStack(alignment: .leading, spacing: Theme.s2) {
                if model.audio.isRunning || model.isFinalizingDictation {
                    BreathRibbon(level: model.audio.level, mode: model.audio.isRunning ? .live : .working)
                        .frame(height: Theme.toolbarButton)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
                TextField("Your words land here", text: $fieldText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.hkBody)
                    .lineLimit(2...4)
                    .focused($fieldFocused)
            }
            .card(style: .outlined)
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(fieldFocused ? Theme.signal : .clear, lineWidth: Theme.selectedStroke))
            .reveal(2)

            if !spoken.isEmpty {
                CleanupDiff(spoken: spoken, cleaned: cleaned, isExample: isExample)
                    .padding(.top, Theme.s4)
                    .transition(.opacity.combined(with: .offset(y: Theme.figureGap)))
            } else {
                Button("No mic handy? Show an example") { showExample() }
                    .buttonStyle(.plain)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, Theme.s3)
            }
        }
        .animation(Theme.gentle, value: spoken)
        .animation(Theme.snappy, value: model.audio.isRunning)
        .onAppear { fieldFocused = true }
        .onChange(of: model.dictationResultGeneration) { _, _ in
            let result = model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { return }
            spoken = model.rawDictationText
            cleaned = result
            isExample = false
            fieldText = result
            passed()
        }
    }

    private func showExample() {
        spoken = CleanupPreview.practicePhrase
        cleaned = CleanupPreview.clean(spoken)
        isExample = true
        fieldText = cleaned
    }
}

/// What was said, with the words cleanup removed struck through, then what was typed.
private struct CleanupDiff: View {
    var spoken: String
    var cleaned: String
    var isExample: Bool

    var body: some View {
        let words = CleanupPreview.words(raw: spoken, cleaned: cleaned)
        let removed = words.filter(\.removed).count
        VStack(alignment: .leading, spacing: Theme.s2) {
            SectionLabel(title: isExample ? "Example: said" : "You said")
            words.reduce(Text("")) { line, word in
                line + Text(word.text)
                    .foregroundStyle(word.removed ? Theme.ink3 : Theme.ink)
                    .strikethrough(word.removed, color: Theme.ink3)
                + Text(" ")
            }
            .font(.hkCallout)
            SectionLabel(title: "HushKey typed").padding(.top, Theme.s1)
            Text(cleaned).font(.hkCallout.weight(.medium))
            Text(removed == 0
                 ? "Nothing needed cleaning that time. Try it with the “um” and the “no”."
                 : "Took out \(removed) \(removed == 1 ? "word" : "words"): the filler and the slip you corrected.")
                .font(.hkCaption)
                .foregroundStyle(removed == 0 ? Theme.ink3 : Theme.signal)
                .padding(.top, Theme.s1)
        }
        .card(padding: Theme.s4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 5 Whisper

private struct WhisperStep: View {
    @Environment(AppModel.self) private var model
    var speakingPeak: Float
    var passed: () -> Void
    @State private var heard = ""
    @State private var matched = false
    @State private var loudness: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeading(step: .whisper,
                        subtitle: "Hold \(shortcutPhrase(model)) and whisper, as quietly as you like:")
            Text("“\(WhisperCheck.phrase)”")
                .font(.hkTitle2)
                .padding(.bottom, Theme.s4)
                .reveal(1)
            VoiceRibbon(level: model.audio.level,
                        mode: model.audio.isRunning ? .live : model.isFinalizingDictation ? .working : .rest,
                        height: Theme.s8)
                .reveal(2)

            Group {
                if matched {
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        PassedLine(text: "Heard: “\(heard)”")
                        if let loudness {
                            Text("That was about \(loudness)% as loud as your speaking voice. A whisper is enough.")
                                .font(.hkCallout).foregroundStyle(Theme.ink2)
                        }
                    }
                } else if !heard.isEmpty {
                    Text("HushKey heard “\(heard)”. Try once more, a little closer to the mic.")
                        .font(.hkCallout).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, Theme.s4)

            Spacer(minLength: Theme.s4)
            Text("No account and no time limits. Your voice and words stay on this Mac.")
                .font(.hkCaption)
                .foregroundStyle(Theme.ink3)
                .padding(.bottom, Theme.s2)
        }
        .animation(Theme.gentle, value: matched)
        .animation(Theme.gentle, value: heard)
        .onChange(of: model.dictationResultGeneration) { _, _ in
            let result = model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { return }
            heard = result
            guard WhisperCheck.matches(result) else { return }
            matched = true
            loudness = WhisperCheck.relativeLoudness(whisperPeak: model.audio.peakLevel, speakingPeak: speakingPeak)
            passed()
        }
    }
}
