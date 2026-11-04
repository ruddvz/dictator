import AVFoundation
import SwiftUI

struct DictationView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearHistory = false
    @State private var historySearch = ""
    @State private var searching = false
    @State private var reader = HistoryReader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                header.reveal(0)
                HStack(alignment: .top, spacing: Theme.s4) {
                    HeroCard().reveal(1)
                    statsCard.frame(width: 248).reveal(2)
                }
                .fixedSize(horizontal: false, vertical: true)
                if showsComposer {
                    composer
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                removal: .opacity))
                }
                historySection.reveal(3)
            }
            .pageLayout(maxWidth: Theme.homeWidth)
            .animation(Theme.gentle, value: showsComposer)
        }
        .onDisappear { reader.stop() }
        .scrollIndicators(.automatic)
        .confirmationDialog(!model.dictationHistoryArchiveUnreadable
                            ? "Delete all recent dictations?" : "Remove unreadable dictation archive?",
                            isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button(!model.dictationHistoryArchiveUnreadable ? "Delete history" : "Remove archive",
                   role: .destructive) { model.clearDictationHistory() }
        } message: {
            if let recoveryCopyURL = model.dictationHistoryRecoveryCopyURL {
                Text("HushKey kept a recovery copy at \(recoveryCopyURL.path). Removing the unreadable file lets new dictations save normally.")
            } else if model.dictationHistoryArchiveUnreadable {
                Text("HushKey could not make a recovery copy. The original file remains in place until you remove it.")
            } else {
                Text("This deletes saved dictations from this Mac. It does not delete training recordings.")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.s4) {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("\(greeting), \(firstName)")
                    .font(.hkTitle1)
                    .tracking(-0.3)
                    .accessibilityIdentifier("page.header")
                HStack(alignment: .center, spacing: 6) {
                    Text(holds ? "Hold" : "Press")
                    KeycapShortcut(label: model.dictationShortcut.label, size: 12)
                    Text(model.dictationShortcut.usesFunctionKey
                         ? "in any app and just talk. Double-tap for hands-free."
                         : holds ? "in any app and just talk. Let go to finish."
                         : "in any app to start, and again to finish.")
                }
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                .accessibilityElement(children: .combine)
                if let problem {
                    HStack(spacing: Theme.s2) {
                        Label(problem, icon: .warning)
                            .font(.hkCallout.weight(.medium))
                            .foregroundStyle(Theme.finishing)
                            .fixedSize(horizontal: false, vertical: true)
                        if problemIsAccessibility {
                            Button("Open Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .controlSize(.small)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(Theme.gentle, value: problem)
            Spacer(minLength: Theme.s4)
            recordButton
        }
    }

    /// Good morning / afternoon / evening, by the clock on this Mac.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hey"
        }
    }

    private var holds: Bool {
        model.dictationShortcut.usesFunctionKey || model.dictationCaptureBehavior == .hold
    }

    private var firstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespaces)
        return full.split(separator: " ").first.map(String.init) ?? NSUserName()
    }

    /// The fn key needs Accessibility access, which only the person can grant.
    private var problemIsAccessibility: Bool {
        model.audio.error == nil && model.transcriber.error == nil && model.dictationShortcutNeedsAttention
            && model.dictationShortcutStatus.contains("Accessibility")
    }

    private var problem: String? {
        if let error = model.audio.error ?? model.transcriber.error { return error }
        return model.dictationShortcutNeedsAttention ? model.dictationShortcutStatus : nil
    }

    private var recordButton: some View {
        Button {
            Task { await model.toggleDictation() }
        } label: {
            HStack(spacing: Theme.s2) {
                LiveLevel(model.audio) { MorphIcon(phase: morphPhase, level: $0, lineWidth: 1.8) }
                    .frame(width: 20, height: 20)
                Text(isFinishing ? "Transcribing"
                     : model.audio.isRunning ? "Stop"
                     : model.isStartingDictation || model.isStartingSelectedTextEdit ? "Cancel"
                     : "Dictate")
                    .contentTransition(.interpolate)
            }
            .frame(minWidth: 96)
        }
        .buttonStyle(PrimaryButtonStyle(tint: model.audio.isRunning ? Theme.ink : Theme.signal))
        .disabled(isFinishing)
        .animation(Theme.snappy, value: model.audio.isRunning)
        .help(model.audio.isRunning ? "Stop dictation"
              : model.isStartingDictation ? "Cancel dictation startup" : "Start dictation")
    }

    // MARK: State

    private var isEditingSelection: Bool {
        model.isStartingSelectedTextEdit || model.isSelectedTextEditCapturing || model.isFinalizingSelectedTextEdit
    }

    private var isBusy: Bool {
        model.isStartingDictation || model.audio.isRunning || model.isFinalizingDictation
            || model.transcriber.isFinalizing || isEditingSelection
    }

    private var isFinishing: Bool {
        model.isFinalizingDictation || model.transcriber.isFinalizing || model.isFinalizingSelectedTextEdit
    }

    private var hasText: Bool {
        !model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsComposer: Bool { (isBusy && !isEditingSelection) || hasText }

    private var morphPhase: MorphIcon.Phase {
        model.audio.isRunning ? .listening : model.isStartingDictation || isFinishing ? .working : .idle
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                LiveLevel(model.audio) { MorphIcon(phase: morphPhase == .idle ? .done : morphPhase, level: $0, lineWidth: 2) }
                    .frame(width: 18, height: 18)
                    .foregroundStyle(model.audio.isRunning ? Theme.listening : Theme.ink)
                Text(model.isSelectedTextEditCapturing ? "Listening for your edit"
                     : model.isFinalizingSelectedTextEdit ? "Applying your edit"
                     : model.isStartingDictation
                        ? (model.audio.isStarting ? "Waiting for microphone access" : "Preparing local recognition")
                     : model.audio.isRunning ? "Listening" : isFinishing ? "Transcribing" : "Latest dictation")
                    .font(.system(size: 15, weight: .semibold))
                modeMenu
                if !model.rawDictationText.isEmpty, let target = model.activeDictationTarget {
                    StatusChip(title: target, icon: .window)
                        .help("Dictated from \(target) · \(contextHintSummary)")
                }
                Spacer(minLength: Theme.s2)
                if hasText, !isBusy {
                    Button("Clear", icon: .close) { model.clearCurrentDictation() }
                        .buttonStyle(IconButtonStyle())
                        .help("Clear the current transcript")
                }
            }

            transcriptEditor

            HStack(spacing: Theme.s2) {
                Button("Insert", icon: .insert) { model.insertDictationText() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.insertion.isEnabled || isBusy || !hasText)
                    .help(model.insertion.isEnabled ? "Insert into the app you dictated from" : "Turn on insertion in Settings")
                Button("Copy", icon: .copy) { model.copyDictationText() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isBusy || !hasText)
                if !isBusy, !model.rawDictationText.isEmpty, model.rawDictationText != model.transcriber.text {
                    Button("Original", icon: .undo) { model.restoreRawTranscript() }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Restore the unprocessed on-device recognition")
                }
                Spacer()
                if !model.insertion.status.isEmpty {
                    Text(model.insertion.status)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(model.insertion.status)
                }
            }
        }
        .card(padding: Theme.s4, style: .outlined)
        .animation(Theme.snappy, value: model.audio.isRunning)
    }

    private var modeMenu: some View {
        Menu {
            Picker("Writing mode", selection: Binding(
                get: { model.dictationMode },
                set: { model.dictationMode = $0 })) {
                ForEach(DictationMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label { Text(model.dictationMode.rawValue) } icon: { SymbolGlyph(model.dictationMode.symbol, size: 14) }
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, Theme.s2 + 2)
        .frame(height: 24)
        .background(Theme.well, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .disabled(isBusy)
        .help(modeDescription(model.dictationMode))
    }

    @ViewBuilder
    private var transcriptEditor: some View {
        if isBusy {
            ScrollView {
                Text(model.transcriber.text.isEmpty
                     ? (isFinishing ? "Finishing up…" : "Start talking…")
                     : model.transcriber.text)
                    .font(.system(size: 17))
                    .lineSpacing(3)
                    .foregroundStyle(model.transcriber.text.isEmpty ? Theme.ink3 : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 72, maxHeight: 220)
        } else {
            TextEditor(text: transcriptBinding)
                .font(.system(size: 17))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72, maxHeight: 220)
                .padding(.horizontal, -5) // align TextEditor's inset text with the header
        }
    }

    // MARK: Stats

    /// Lifetime numbers from the same ledger as Insights, so the two always agree. They count
    /// up from zero the first time Home appears, and roll digit by digit when a dictation lands.
    private var statsCard: some View {
        let ledger = model.usageLedger
        let streak = ledger.currentStreak()
        let today = ledger.days[UsageLedger.key(for: Date())]?.words ?? 0
        return Button {
            withAnimation(Theme.snappy) { model.screen = .insights }
        } label: {
            VStack(alignment: .leading, spacing: Theme.s3 + 2) {
                VStack(alignment: .leading, spacing: 2) {
                    statRow(value: ledger.totalWords, label: ledger.totalWords == 1 ? "word dictated" : "words dictated", order: 0)
                    if today > 0 {
                        Text("+\(today.formatted()) today")
                            .font(.hkMeta.weight(.semibold))
                            .foregroundStyle(Theme.signal)
                            .contentTransition(.numericText(value: Double(today)))
                            .transition(.opacity)
                    }
                }
                statRow(value: ledger.wordsPerMinute, label: "words per minute", order: 1)
                statRow(value: streak, label: "day streak", order: 2)
                voiceLines(VoiceProfile(entries: model.dictationHistory, ledger: ledger, readingText: false))
                Rectangle().fill(Theme.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: Theme.s2) {
                    HStack {
                        SectionLabel(title: "Last 12 weeks")
                        Spacer()
                        Glyph(.arrowUpRight)
                            .hushIconSize(12)
                            .foregroundStyle(Theme.ink3)
                    }
                    ActivityHeatmap(counts: ledger.dailyCounts())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(StatsCardStyle())
        .help("Open Insights")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Insights")
    }

    /// Time saved and the voice profile in two quiet lines; Insights has the full cards.
    @ViewBuilder
    private func voiceLines(_ profile: VoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1 + 2) {
            if let saved = profile.timeSavedText {
                Label(saved.prefix(1).uppercased() + saved.dropFirst() + " vs typing", icon: .clock)
                    .help("Words at \(VoiceProfile.typingWordsPerMinute) wpm typing, minus the time you spent speaking")
            }
            if let next = profile.nextUnlock, next.card == .pace {
                Label("Your voice profile in \(next.remaining) dictation\(next.remaining == 1 ? "" : "s")", icon: .waveform)
                    .foregroundStyle(Theme.ink3)
                    .help("After \(VoiceProfile.firstUnlock) dictations, Insights sketches how you talk, from the history on this Mac")
            } else if let summary = Self.voiceSummary(profile) {
                Label(summary, icon: .waveform)
                    .help("Your voice profile, read from the history on this Mac. More in Insights.")
            }
        }
        .hushIconSize(14)
        .font(.hkMeta.weight(.medium))
        .foregroundStyle(Theme.ink2)
        .lineLimit(1)
    }

    /// "Steady voice · night owl", with only the parts that have unlocked and have data.
    static func voiceSummary(_ profile: VoiceProfile) -> String? {
        var parts: [String] = []
        if let pace = profile.pace { parts.append("\(pace.rawValue) voice") }
        if profile.isUnlocked(.peakHours), let peak = profile.peakHours {
            parts.append(parts.isEmpty ? peak.timeOfDay.rawValue : peak.timeOfDay.rawValue.lowercased())
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func statRow(value: Int?, label: String, order: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
            CountingNumber(value: value, delay: 0.15 + Double(order) * 0.08)
                .font(.display(28))
            Text(label)
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
        }
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                SectionLabel(title: groupedHistory.first.map { dayTitle($0.day) } ?? "History")
                Spacer()
                if !model.dictationHistory.isEmpty {
                    if searching || !historySearch.isEmpty {
                        searchField.transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        Button("Search", icon: .search) { searching = true }
                            .buttonStyle(IconButtonStyle())
                            .help("Search history")
                    }
                }
                if !model.dictationHistory.isEmpty || model.dictationHistoryArchiveUnreadable {
                    Menu {
                        Button(!model.dictationHistoryArchiveUnreadable ? "Delete all history…" : "Remove unreadable archive…",
                               role: .destructive) { confirmClearHistory = true }
                    } label: {
                        Glyph(.more)
                    }
                    .menuStyle(.button)
                    .buttonStyle(IconButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(!model.canClearDictationHistory)
                    .help(model.canClearDictationHistory
                          ? "History options" : "Stop dictation before clearing history")
                }
            }
            .animation(Theme.snappy, value: searching)

            if let message = model.dictationHistoryMessage {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(message.hasPrefix("Could not") || message.hasPrefix("This transcript")
                                     ? Theme.finishing : Theme.ink3)
                    .textSelection(.enabled)
            }

            if let deleted = model.deletedDictation {
                DeletedDictationBar(deleted: deleted)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let cancelled = model.cancelledDictation {
                CancelledDictationRow(cancelled: cancelled, isLocked: isBusy)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if model.dictationHistory.isEmpty {
                emptyHistory
            } else if groupedHistory.isEmpty {
                ContentUnavailableView.search(text: historySearch)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .card(style: .outlined)
            } else {
                ForEach(groupedHistory, id: \.day) { group in
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        if group.day != groupedHistory.first?.day {
                            SectionLabel(title: dayTitle(group.day))
                                .padding(.top, Theme.s4)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 {
                                    Rectangle().fill(Theme.hairline).frame(height: 1)
                                }
                                HistoryRow(entry: entry, isLocked: isBusy, reader: reader)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                }
                .animation(Theme.gentle, value: model.dictationHistory.map(\.id))
            }
        }
    }

    private var emptyHistory: some View {
        VStack(spacing: Theme.s3) {
            MorphIcon(phase: .idle, lineWidth: 2.4)
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.ink3)
            Text(model.savesDictationHistory ? "Your dictations collect here" : "History is off")
                .font(.hkHeadline)
            Text(model.savesDictationHistory
                 ? "Each one is kept on this Mac, grouped by day, ready to copy or edit again."
                 : "Turn it on in Settings to keep recent dictations on this Mac.")
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.s6)
        .card(style: .outlined)
    }

    private var searchField: some View {
        HStack(spacing: Theme.s2) {
            Glyph(.search).foregroundStyle(Theme.ink3)
            TextField("Search history", text: $historySearch)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .accessibilityLabel("Search saved dictations")
                .onExitCommand {
                    historySearch = ""
                    searching = false
                }
            Button("Close search", icon: .close) {
                historySearch = ""
                searching = false
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink3)
        }
        .font(.hkCallout)
        .padding(.horizontal, Theme.s3)
        .frame(height: Theme.controlHeight - 4)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private struct DayGroup {
        var day: Date
        var entries: [DictationHistoryEntry]
    }

    private var groupedHistory: [DayGroup] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? model.dictationHistory : model.dictationHistory.filter { entry in
            entry.text.localizedCaseInsensitiveContains(query) ||
                (entry.rawText?.localizedCaseInsensitiveContains(query) ?? false)
        }
        let calendar = Calendar.current
        var groups: [DayGroup] = []
        for entry in matching {
            let day = calendar.startOfDay(for: entry.createdAt)
            if groups.last?.day == day { groups[groups.count - 1].entries.append(entry) }
            else { groups.append(DayGroup(day: day, entries: [entry])) }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { model.transcriber.text }, set: { model.editCurrentDictation($0) })
    }

    private func modeDescription(_ mode: DictationMode) -> String {
        switch mode {
        case .automatic: "Picks Natural, Message, Email, or Code from the app in front when you start."
        case .natural: "Keeps the on-device transcript with your vocabulary, snippets, and optional spoken corrections."
        case .message: "Adds common message terms as recognition hints; “new line” becomes a line break."
        case .email: "Adds email terms as recognition hints; “new paragraph” starts a new paragraph."
        case .code: "Formats spoken programming tokens such as parentheses, underscores, arrows, and new lines."
        }
    }

    private var contextHintSummary: String {
        guard model.usesNearbyTextHints else { return "nearby hints off" }
        return model.usedNearbyTextHints ? "nearby terms used" : "no nearby terms available"
    }
}

/// The home hero: a deep panel with a slow ambient field, the next useful step on the left,
/// and HushKey's breath ribbon on the right, which listens along whenever a dictation runs.
private struct HeroCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage("dismissedNextSteps") private var dismissedRaw = ""
    @State private var windowVisible = true

    private struct Step {
        var id: String
        var title: String
        /// Last words of the title, set in sage.
        var accent: String
        var detail: String
        var action: String
        var dismissable = true
        var perform: (AppModel) -> Void
    }

    private var step: Step {
        let dismissed = Set(dismissedRaw.split(separator: ",").map(String.init))
        let candidates: [Step] = [
            model.insertion.isEnabled ? nil : Step(
                id: "insertion", title: "Type straight into", accent: "any app",
                detail: "Turn on insertion and finished dictations land where your cursor is.",
                action: "Turn on insertion") { model in
                    UserDefaults.standard.set(SettingsView.Section.insertion.rawValue, forKey: "settingsSection")
                    model.screen = .settings
                },
            !model.dictationToneSettings.tones.isEmpty ? nil : Step(
                id: "style", title: "Make HushKey sound like", accent: "you",
                detail: "Casual in Messages, formal in Mail. Pick a style for each kind of app.",
                action: "Choose styles") { $0.screen = .style },
            !model.dictationTerms.isEmpty || !model.dictationSnippets.isEmpty ? nil : Step(
                id: "vocabulary", title: "Teach HushKey", accent: "your words",
                detail: "Add names and jargon once. Recognition and spelling follow everywhere.",
                action: "Add words") { $0.screen = .personalization },
            Step(id: "silent", title: "Go quiet with", accent: "AirPods",
                 detail: "Train a few words or head gestures in the Silent Lab and keep your hands free.",
                 action: "Open Silent Lab") { $0.screen = .setup },
        ].compactMap { $0 }
        return candidates.first { !dismissed.contains($0.id) } ?? Step(
            id: "whisper", title: "Whisper it.", accent: "HushKey still hears you.",
            detail: "Quiet speech is transcribed on this Mac, and nothing leaves it.",
            action: "Try a whisper", dismissable: false) { model in
                Task { await model.toggleDictation() }
            }
    }

    private var ribbonMode: BreathRibbon.Mode {
        if model.audio.isRunning { return .live }
        if model.isStartingDictation { return .waiting }
        if model.isFinalizingDictation || model.transcriber.isFinalizing { return .working }
        return .rest
    }

    var body: some View {
        let step = step
        ZStack(alignment: .topTrailing) {
            // Title at the top, action at the bottom, whatever height the stats card sets.
            VStack(alignment: .leading, spacing: Theme.s2) {
                (Text(step.title + " ") + Text(step.accent).foregroundStyle(Theme.heroGlow))
                    .font(.display(30))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.heroInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(.hkCallout)
                    .foregroundStyle(Theme.heroInk2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.s4)
                Button(step.action) { step.perform(model) }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.heroInk, foreground: Theme.heroBase))
            }
            .frame(maxWidth: 420, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.s6 - 4)
            .id(step.id)
            .transition(.opacity)

            if step.dismissable {
                Button("Dismiss", icon: .close) {
                    withAnimation(Theme.gentle) {
                        dismissedRaw = (dismissedRaw.isEmpty ? "" : dismissedRaw + ",") + step.id
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.heroInk2)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .padding(Theme.s2)
                .help("Hide this suggestion")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 200)
        .background {
            IsolatedHost { LiveLevel(model.audio) { HeroBackdrop(level: $0, mode: ribbonMode, visible: windowVisible) } }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous)
            .strokeBorder(Theme.heroInk.opacity(0.08), lineWidth: 1))
        .onWindowVisibilityChange { windowVisible = $0 }
        .animation(Theme.gentle, value: step.id)
    }
}

/// The hero's moving layer: the ambient field, and the voice ribbon while a dictation runs.
private struct HeroBackdrop: View {
    var level: Float
    var mode: BreathRibbon.Mode
    var visible: Bool

    var body: some View {
        GeometryReader { geo in
            let focus = UnitPoint(x: 0.78, y: 0.5)
            let ribbon = AmbientField.ribbonRect(in: geo.size, focus: focus)
            ZStack {
                // At rest the field draws the ribbon itself; a live one runs at 60 fps only while dictating.
                AmbientField(focus: focus, paused: !visible,
                             restingRibbon: mode == .rest ? Theme.heroGlow : nil)
                if mode != .rest {
                    BreathRibbon(level: level, mode: mode, tint: Theme.heroGlow, paused: !visible)
                        .frame(width: ribbon.width, height: ribbon.height)
                        .position(x: ribbon.midX, y: ribbon.midY)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// One saved dictation: time column, text with a meta line (app · duration · words), and
/// Wispr-style hover actions in a floating pill: Copy (turns into a check), Edit again, and ⋯.
/// A long row opens in place when clicked.
private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var entry: DictationHistoryEntry
    var isLocked: Bool
    var reader: HistoryReader

    @State private var isHovering = false
    @State private var copied = false
    @State private var expanded = false

    private var isReading: Bool { reader.speakingID == entry.id }
    private var isRetranscribing: Bool { model.retranscribingDictationID == entry.id }
    private var showsActions: Bool { isHovering || isReading || copied }
    /// Long dictations show three lines; a click opens the rest.
    private var isLong: Bool { entry.text.count > 220 || entry.text.filter(\.isNewline).count > 2 }
    /// The row opens with a firm spring; with Reduce Motion it just changes.
    private var expandAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s4) {
            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(isHovering ? Theme.ink : Theme.ink2)
                .frame(width: 82, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                entryText
                metaLine
            }
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, 15)
        .frame(minHeight: Theme.listRow)
        .background(isHovering ? Theme.well : .clear)
        .overlay(alignment: .topTrailing) { actionPill.padding(Theme.s2) }
        .contentShape(Rectangle())
        .onTapGesture { if isLong { toggleExpanded() } }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: expanded ? "Show less" : "Show full text") { if isLong { toggleExpanded() } }
    }

    @ViewBuilder
    private var entryText: some View {
        let text = Text(entry.text)
            .font(.hkBody)
            .lineSpacing(3)
            .lineLimit(isLong && !expanded ? 3 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        // A collapsed long row takes the click to open; once open its text can be selected.
        if isLong && !expanded { text } else { text.textSelection(.enabled) }
    }

    private var metaLine: some View {
        HStack(spacing: Theme.s2) {
            Text(entry.metaLine)
                .font(.hkMeta.monospacedDigit())
                .foregroundStyle(Theme.ink3)
            if entry.cleanedText != nil {
                Text("Original recognition")
                    .font(.hkMeta.weight(.medium))
                    .foregroundStyle(Theme.ink2)
            }
            if isRetranscribing {
                ProgressView().controlSize(.mini)
                Text("Re-transcribing…").font(.hkMeta).foregroundStyle(Theme.ink2)
            }
            if isLong {
                Button(action: toggleExpanded) {
                    HStack(spacing: 3) {
                        Text(expanded ? "Show less" : "Show more")
                        Glyph(.chevronDown, size: 12)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .font(.hkMeta.weight(.medium))
                .foregroundStyle(Theme.ink2)
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Show less text" : "Show full text")
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(expandAnimation) { expanded.toggle() }
    }

    /// The floating capsule over the row's top right. It fades and slides in on hover, each
    /// button a beat after the one before.
    private var actionPill: some View {
        HStack(spacing: 0) {
            action(copied ? "Copied" : "Copy", copied ? .check : .copy, order: 0) {
                model.copyDictation(entry)
                withAnimation(Theme.snappy) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    withAnimation(Theme.snappy) { copied = false }
                }
            }
            .foregroundStyle(copied ? Theme.signal : Theme.ink2)
            action("Edit again", .edit, order: 1) { model.restoreDictation(entry) }
                .disabled(isLocked)
            Menu { menuItems } label: { Glyph(.more) }
                .menuStyle(.button)
                .buttonStyle(IconButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                .opacity(showsActions ? 1 : 0)
                .animation(Theme.snappy.delay(showsActions ? 2 * 0.03 : 0), value: showsActions)
        }
        .padding(2)
        .background(Theme.sheet, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .opacity(showsActions ? 1 : 0)
        .offset(x: showsActions ? 0 : 6)
        .animation(.easeOut(duration: 0.12), value: showsActions)
        .allowsHitTesting(showsActions)
    }

    /// The ⋯ menu, also the right-click menu.
    @ViewBuilder
    private var menuItems: some View {
        if entry.cleanedText != nil {
            Button("Redo cleanup", systemImage: "arrow.uturn.forward") { model.toggleCleanup(entry) }
                .disabled(isLocked)
        } else if entry.undoingCleanup() != nil {
            Button("Undo cleanup", systemImage: "arrow.uturn.backward") { model.toggleCleanup(entry) }
                .disabled(isLocked)
        }
        stateButton("Paste again", systemImage: "text.insert", state: model.pasteAgainState(for: entry)) {
            Task { await model.pasteDictationAgain(entry) }
        }
        stateButton("Re-transcribe with \(model.retranscribeEngine(for: entry)?.title ?? "the other engine")",
                    systemImage: "waveform", state: model.retranscribeState(for: entry)) {
            Task { await model.retranscribeDictation(entry) }
        }
        Divider()
        Button(isReading ? "Stop reading" : "Read aloud", systemImage: isReading ? "stop.fill" : "speaker.wave.2") {
            reader.toggle(entry)
        }
        if let raw = entry.rawText, raw != entry.text {
            Button("Copy original recognition", systemImage: "doc.on.clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(raw, forType: .string)
            }
        }
        Button("Transform this dictation", systemImage: "wand.and.stars") {
            model.restoreDictation(entry)
            model.screen = .transforms
        }
        .disabled(isLocked)
        Button("Add a word to Vocabulary", systemImage: "character.book.closed") {
            withAnimation(Theme.snappy) { model.screen = .personalization }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            reader.stop(entry)
            withAnimation(reduceMotion ? nil : Theme.gentle) { model.deleteDictation(entry) }
        }
        .disabled(isRetranscribing)
    }

    /// A menu item that is left out, runs, or shows why it can't run as its greyed-out title.
    @ViewBuilder
    private func stateButton(_ title: String, systemImage: String, state: DictationHistoryActionState,
                             perform: @escaping () -> Void) -> some View {
        switch state {
        case .hidden: EmptyView()
        case .available: Button(title, systemImage: systemImage, action: perform)
        case .unavailable(let reason): Button(reason, systemImage: systemImage) {}.disabled(true)
        }
    }

    private func action(_ title: String, _ icon: HushIcon, order: Int, perform: @escaping () -> Void) -> some View {
        Button(title, icon: icon, action: perform)
            .buttonStyle(IconButtonStyle())
            .contentTransition(.symbolEffect(.replace))
            .help(title)
            .opacity(showsActions ? 1 : 0)
            .scaleEffect(showsActions ? 1 : 0.7)
            .animation(Theme.snappy.delay(showsActions ? Double(order) * 0.03 : 0), value: showsActions)
    }
}

/// "Dictation deleted · Undo", shown for a few seconds after a History delete.
private struct DeletedDictationBar: View {
    @Environment(AppModel.self) private var model
    var deleted: DeletedDictation

    var body: some View {
        HStack(spacing: Theme.s2) {
            Glyph(.trash, size: 14).foregroundStyle(Theme.ink3)
            Text("Dictation deleted")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
            Spacer()
            Button("Undo") { withAnimation(Theme.gentle) { model.undoDeleteDictation() } }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.signal)
                .help("Put this dictation back")
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, 10)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        .task(id: deleted.entry.id) {
            try? await Task.sleep(for: .seconds(DeletedDictation.undoSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.gentle) { model.expireDeletedDictation(deleted.entry.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation deleted")
    }
}

/// Reads one saved dictation aloud with the system voice, so you can hear what was typed.
/// HushKey keeps no audio of past dictations on disk, so this is the "play" Wispr offers.
@Observable
final class HistoryReader: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var speakingID: UUID?
    @ObservationIgnored private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()

    func toggle(_ entry: DictationHistoryEntry) {
        if speakingID == entry.id { stop(); return }
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = entry.id
        synthesizer.speak(AVSpeechUtterance(string: entry.text))
    }

    func stop(_ entry: DictationHistoryEntry? = nil) {
        guard entry == nil || entry?.id == speakingID else { return }
        if speakingID != nil { synthesizer.stopSpeaking(at: .immediate) }
        speakingID = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.speakingID = nil }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { if !synthesizer.isSpeaking { self.speakingID = nil } }
    }
}

/// A whole number that counts up from zero when it first appears, then rolls to new values.
private struct CountingNumber: View {
    var value: Int?
    var delay: Double = 0
    @State private var shown: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(value == nil ? "–" : shown.formatted())
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear {
                guard let value else { return }
                if reduceMotion { shown = value; return }
                withAnimation(.spring(response: 0.9, dampingFraction: 0.9).delay(delay)) { shown = value }
            }
            .onChange(of: value) { _, new in
                withAnimation(Theme.gentle) { shown = new ?? 0 }
            }
            .accessibilityLabel(value.map { "\($0)" } ?? "none")
    }
}

/// The last cancelled dictation, offered back like Wispr's "dismissed, Recover" row. The audio
/// only lives in memory for this session.
private struct CancelledDictationRow: View {
    @Environment(AppModel.self) private var model
    var cancelled: CancelledDictation
    var isLocked: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.s4) {
            Text(cancelled.cancelledAt, style: .time)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .frame(width: 82, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("You cancelled a \(cancelled.durationLabel) dictation\(cancelled.appName.map { " in \($0)" } ?? "").")
                    .font(.hkBody)
                    .foregroundStyle(Theme.ink2)
                Text("Kept in memory until you quit HushKey. Nothing was typed or saved.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: Theme.s2)
            Button("Restore to HushKey", icon: .undo) {
                Task { await model.recoverCancelledDictation() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isLocked)
            .help("Transcribe it on this Mac and add it to History. It will not type into another app.")
            Button("Discard", icon: .close) { withAnimation(Theme.snappy) { model.discardCancelledDictation() } }
                .buttonStyle(IconButtonStyle())
                .help("Forget this recording")
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s3)
        .frame(minHeight: Theme.listRow)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cancelled dictation, \(cancelled.durationLabel)")
    }
}

/// The home stats card: a card that lifts slightly on hover and opens Insights.
private struct StatsCardStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .card(padding: Theme.s5)
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: hovering ? 1 : 0))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.snappy, value: hovering)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}
