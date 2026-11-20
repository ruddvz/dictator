import AVFoundation
import SwiftUI

struct DictationView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearHistory = false
    @State private var historySearch = ""
    @State private var searching = false
    @State private var hoveringFigures = false
    @State private var reader = HistoryReader()

    var body: some View {
        ScrollView {
            PageColumn(maxWidth: Theme.homeWidth) {
                header
                VoiceBand(holds: holds).reveal(1)
                // Hallmark (app screens): the history is Home's signature object, so nothing
                // above it competes: one quiet line of figures and, at most, one next step.
                if model.usageLedger.totalWords > 0 {
                    figuresLine.reveal(2)
                }
                NextStepRow().reveal(3)
                if showsComposer {
                    composer
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                removal: .opacity))
                }
                historySection.reveal(4)
            }
            .animation(Theme.gentle, value: showsComposer)
        }
        .task(id: model.dictationShortcutNeedsAttention) {
            guard model.dictationShortcutNeedsAttention else { return }
            while !Task.isCancelled && model.dictationShortcutNeedsAttention {
                model.refreshFunctionKeyStatus()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear { reader.stop() }
        .scrollIndicators(.automatic)
        .confirmationDialog(!model.dictationHistoryArchiveUnreadable
                            ? "Delete all recent dictations?" : "Remove unreadable dictation archive?",
                            isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button(!model.dictationHistoryArchiveUnreadable ? "Delete all dictations" : "Remove archive",
                   role: .destructive) { model.clearDictationHistory() }
        } message: {
            if let recoveryCopyURL = model.dictationHistoryRecoveryCopyURL {
                Text("Dictator kept a recovery copy at \(recoveryCopyURL.path). Removing the unreadable file lets new dictations save normally.")
            } else if model.dictationHistoryArchiveUnreadable {
                Text("Dictator could not make a recovery copy. The original file remains in place until you remove it.")
            } else {
                Text("This deletes saved dictations from this Mac. It does not delete training recordings.")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        PageHeader(title: "Home") {
            if let problem {
                HStack(spacing: Theme.s2) {
                    Label(problem, icon: .warning)
                        .font(.hkCallout.weight(.medium))
                        .foregroundStyle(Theme.finishing)
                        .fixedSize(horizontal: false, vertical: true)
                    if problemIsAccessibility {
                        Button("Check access") { model.requestFunctionKeyAccessibilityAccess() }
                            .buttonStyle(SecondaryButtonStyle())
                            .controlSize(.small)
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .controlSize(.small)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                }
        } actions: {
            recordButton
        }
        .animation(Theme.gentle, value: problem)
    }

    private var holds: Bool {
        model.dictationShortcut.usesFunctionKey || model.dictationCaptureBehavior == .hold
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
                LiveLevel(model.audio) { level in
                    StateIcon(phase: statePhase, level: level)
                }
                    .frame(width: Theme.iconColumn, height: Theme.iconColumn)
                Text(isFinishing ? "Transcribing"
                     : model.audio.isRunning ? "Stop"
                     : model.isStartingDictation || model.isStartingSelectedTextEdit ? "Cancel"
                     : "Dictate")
                    .contentTransition(.interpolate)
            }
            .frame(minWidth: Theme.buttonMinWidth)
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

    private var statePhase: StateIcon.Phase {
        model.audio.isRunning ? .listening : model.isStartingDictation || isFinishing ? .working : .idle
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                LiveLevel(model.audio) { level in
                    StateIcon(phase: statePhase == .idle ? .done : statePhase, level: level)
                }
                    .frame(width: Theme.iconL, height: Theme.iconL)
                    .foregroundStyle(model.audio.isRunning ? Theme.listening : Theme.ink)
                Text(model.isSelectedTextEditCapturing ? "Listening for your edit"
                     : model.isFinalizingSelectedTextEdit ? "Applying your edit"
                     : model.isStartingDictation
                        ? (model.audio.isStarting ? "Waiting for microphone…" : "Getting ready…")
                     : model.audio.isRunning ? "Listening" : isFinishing ? "Transcribing" : "Latest dictation")
                    .font(.hkCallout.weight(.semibold))
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

            if let suggestion = model.correctionLearningSuggestion {
                HStack(spacing: Theme.s3) {
                    VStack(alignment: .leading, spacing: Theme.s1) {
                        Text("Learn this correction?")
                            .font(.hkControl.weight(.semibold))
                        Text("“\(suggestion.recognized)” → “\(suggestion.corrected)” · only the corrected word is saved on this Mac")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(2)
                    }
                    Spacer(minLength: Theme.s2)
                    Button("Add word") { model.learnCurrentCorrectionSuggestion() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { model.dismissCorrectionLearningSuggestion() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Dismiss vocabulary suggestion")
                }
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, Theme.s2)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let feedback = model.correctionLearningFeedback {
                HStack(spacing: Theme.s2) {
                    Text(feedback)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                    Spacer(minLength: Theme.s2)
                    if model.canUndoCorrectionLearning {
                        Button("Undo") { model.undoCorrectionLearning() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, Theme.s2)
                .transition(.opacity)
            }

            HStack(spacing: Theme.s2) {
                Button("Insert", icon: .insert) { model.insertDictationText() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.insertion.isEnabled || isBusy || !hasText)
                    .help(model.insertion.isEnabled ? "Insert into the app you dictated from" : "Turn on typing in Settings › Typing")
                Button("Copy", icon: .copy) { model.copyDictationText() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isBusy || !hasText)
                if !isBusy, !model.rawDictationText.isEmpty, model.rawDictationText != model.transcriber.text {
                    Button("Original", icon: .undo) { model.restoreRawTranscript() }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Show what you said before cleanup")
                }
                Spacer()
                if !model.insertion.status.isEmpty {
                    Text(model.insertion.status)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(model.insertion.status)
                }
            }
        }
        .card(padding: Theme.s4, style: .outlined)
        .animation(Theme.snappy, value: model.audio.isRunning)
        .animation(Theme.snappy, value: model.correctionLearningSuggestion)
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
            Label { Text(model.dictationMode.rawValue) } icon: { SymbolGlyph(model.dictationMode.symbol, size: Theme.iconS) }
                .font(.hkCaption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, Theme.s3)
        .frame(height: Theme.chipHeight)
        .background(Theme.well, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
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
                    .font(.hkTranscript)
                    .lineSpacing(Theme.leading)
                    .foregroundStyle(model.transcriber.text.isEmpty ? Theme.ink3 : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: Theme.editorShort, maxHeight: Theme.editorTall)
        } else {
            TextEditor(text: transcriptBinding)
                .font(.hkTranscript)
                .lineSpacing(Theme.leading)
                .scrollContentBackground(.hidden)
                .frame(minHeight: Theme.editorShort, maxHeight: Theme.editorTall)
                .padding(.horizontal, -Theme.textEditorInset) // align TextEditor's inset text with the header
        }
    }

    // MARK: Stats

    /// Lifetime figures from the same ledger as Insights, set as figure + label in tabular
    /// numerals on one line. The whole line opens Insights.
    private var figuresLine: some View {
        let ledger = model.usageLedger
        let streak = ledger.currentStreak()
        let today = ledger.days[UsageLedger.key(for: Date())]?.words ?? 0
        let saved = VoiceProfile(entries: model.dictationHistory, ledger: ledger, readingText: false).timeSavedText
        return Button {
            withAnimation(Theme.snappy) { model.screen = .insights }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.s6) {
                figure(ledger.totalWords, ledger.totalWords == 1 ? "word" : "words", order: 0)
                if today > 0 { figure(today, "today", order: 1) }
                figure(ledger.wordsPerMinute, "per minute", order: 2)
                figure(streak, streak == 1 ? "day in a row" : "days in a row", order: 3)
                if let saved {
                    Text(saved.prefix(1).uppercased() + saved.dropFirst())
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(1)
                        .help("Words at \(VoiceProfile.typingWordsPerMinute) wpm typing, minus the time you spent speaking")
                }
                Spacer(minLength: Theme.s4)
                Text("Insights")
                    .font(.hkCallout.weight(.medium))
                    .foregroundStyle(hoveringFigures ? Theme.ink : Theme.ink3)
            }
            .padding(.vertical, Theme.s3)
            .overlay(alignment: .top) { RowDivider() }
            .overlay(alignment: .bottom) { RowDivider() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringFigures = $0 }
        .help("Open Insights")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Insights")
    }

    private func figure(_ value: Int?, _ label: String, order: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.figureGap) {
            CountingNumber(value: value, delay: 0.15 + Double(order) * 0.08)
                .font(.hkDisplayBand)
            Text(label)
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
        }
        .fixedSize()
    }

    /// "Steady voice, night owl", with only the parts that have unlocked and have data.
    static func voiceSummary(_ profile: VoiceProfile) -> String? {
        var parts: [String] = []
        if let pace = profile.pace { parts.append("\(pace.rawValue) voice") }
        if profile.isUnlocked(.peakHours), let peak = profile.peakHours {
            parts.append(parts.isEmpty ? peak.timeOfDay.rawValue : peak.timeOfDay.rawValue.lowercased())
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            SectionTitle(groupedHistory.first.map { dayTitle($0.day) } ?? "History") {
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
                        Button(!model.dictationHistoryArchiveUnreadable ? "Delete all dictations…" : "Remove unreadable archive…",
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
                    .font(.hkCaption)
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
                    .frame(maxWidth: .infinity, minHeight: Theme.editorMedium)
                    .card(style: .outlined)
            } else {
                ForEach(groupedHistory, id: \.day) { group in
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        if group.day != groupedHistory.first?.day {
                            SectionTitle(dayTitle(group.day))
                                .padding(.top, Theme.sectionGap)
                        }
                        // A ruled list, not a boxed card: rows sit on the page between hairlines.
                        // Rows keep their inner padding for the hover wash, so the list moves
                        // out by it and the text lines up with the headings above.
                        LazyVStack(spacing: 0) {
                            RowDivider().padding(.horizontal, Theme.rowPaddingH)
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 {
                                    RowDivider().padding(.horizontal, Theme.rowPaddingH)
                                }
                                HistoryRow(entry: entry, isLocked: isBusy, reader: reader)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, -Theme.rowPaddingH)
                    }
                }
                .animation(Theme.gentle, value: model.dictationHistory.map(\.id))
            }
        }
    }

    /// Empty history sits on the page under its heading: what will collect here and how.
    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(model.savesDictationHistory ? "Nothing dictated yet" : "History is off")
                .font(.hkHeadline)
            Text(model.savesDictationHistory
                 ? "Each dictation is kept here on this Mac, grouped by day, ready to copy or edit again."
                 : "Turn it on in Settings › Data & privacy to keep recent dictations on this Mac.")
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: Theme.readingWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.rowPaddingV)
        .overlay(alignment: .top) { RowDivider() }
    }

    private var searchField: some View {
        SearchField(prompt: "Search history", text: $historySearch,
                    accessibilityLabel: "Search saved dictations") {
            historySearch = ""
            searching = false
        }
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
/// and Dictator's breath ribbon on the right, which listens along whenever a dictation runs.
/// Home's signature: the voice band. The same dark sage field as the pill's world, with the
/// breath ribbon resting on the right. It says how to dictate in Dictator's serif voice, and
/// while you dictate it is the live instrument: the ribbon follows your voice and the line
/// says what is happening. Motion is state: at rest the ribbon is drawn, not animated.
private struct VoiceBand: View {
    @Environment(AppModel.self) private var model
    var holds: Bool
    @State private var windowVisible = true
    @State private var hovering = false

    private var mode: BreathRibbon.Mode {
        if model.audio.isRunning { return .live }
        if model.isStartingDictation { return .waiting }
        if model.isFinalizingDictation || model.transcriber.isFinalizing { return .working }
        return .rest
    }

    private var line: String {
        switch mode {
        case .live: "Listening."
        case .waiting: "Opening the microphone…"
        case .working: "Writing it down…"
        default:
            model.dictationShortcut.usesFunctionKey || holds
                ? "Hold \(model.dictationShortcut.label) and talk."
                : "Press \(model.dictationShortcut.label) and talk."
        }
    }

    private var detail: String {
        switch mode {
        case .live: holds ? "Let go to finish. Esc cancels." : "Press the shortcut again to finish. Esc cancels."
        case .waiting, .working: "Everything happens on this Mac."
        default:
            model.dictationShortcut.usesFunctionKey
                ? "In any app. Double-press for hands-free. Nothing leaves this Mac."
                : holds ? "In any app. Let go to finish. Nothing leaves this Mac."
                : "In any app, and again to finish. Nothing leaves this Mac."
        }
    }

    var body: some View {
        Button {
            Task { await model.toggleDictation() }
        } label: {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text(line)
                    .font(.display(34))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.heroInk)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.hkCallout)
                    .foregroundStyle(Theme.heroInk2)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: 440, alignment: .leading)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .padding(.horizontal, Theme.s6)
            .padding(.vertical, Theme.s5)
            .background {
                IsolatedHost {
                    LiveLevel(model.audio) {
                        VoiceBandBackdrop(level: $0, mode: mode, visible: windowVisible, inviting: hovering)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(Theme.heroInk.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(mode == .working)
        .animation(Theme.gentle, value: mode)
        .onWindowVisibilityChange { windowVisible = $0 }
        .help(model.audio.isRunning ? "Stop dictation" : "Start dictation")
        .accessibilityLabel(line + " " + detail)
    }
}

/// One suggested next step, inline above the history: a plain sentence, one line of detail,
/// a secondary button and a dismiss. Nothing when every step is done or dismissed, so the
/// Dictate button stays the page's one primary action.
private struct NextStepRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage("dismissedNextSteps") private var dismissedRaw = ""

    private struct Step {
        var id: String
        var title: String
        var detail: String
        var action: String
        var perform: (AppModel) -> Void
    }

    private var step: Step? {
        let dismissed = Set(dismissedRaw.split(separator: ",").map(String.init))
        let candidates: [Step] = [
            model.insertion.isEnabled ? nil : Step(
                id: "insertion", title: "Type straight into any app",
                detail: "macOS Accessibility is separate. Enable Dictator's typing switch to insert at your cursor.",
                action: "Enable typing") { model in
                    UserDefaults.standard.set(SettingsView.Section.insertion.rawValue, forKey: "settingsSection")
                    model.screen = .settings
                },
            !model.dictationToneSettings.tones.isEmpty ? nil : Step(
                id: "style", title: "Make Dictator sound like you",
                detail: "Casual in Messages, formal in Mail. Pick a style for each kind of app.",
                action: "Choose styles") { $0.screen = .style },
            !model.dictationTerms.isEmpty || !model.dictationSnippets.isEmpty ? nil : Step(
                id: "vocabulary", title: "Teach Dictator your words",
                detail: "Add names and jargon once. Recognition and spelling follow everywhere.",
                action: "Add words") { $0.screen = .personalization },
            Step(id: "silent", title: "Go quiet with AirPods",
                 detail: "Train a few words or head gestures in the Silent Lab.",
                 action: "Open Silent Lab") { $0.screen = .setup },
        ].compactMap { $0 }
        return candidates.first { !dismissed.contains($0.id) }
    }

    var body: some View {
        if let step {
            HStack(alignment: .center, spacing: Theme.s4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.hkHeadline)
                        .foregroundStyle(Theme.ink)
                    Text(step.detail)
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.s4)
                Button(step.action) { step.perform(model) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Dismiss", icon: .close) {
                    withAnimation(Theme.gentle) {
                        dismissedRaw = (dismissedRaw.isEmpty ? "" : dismissedRaw + ",") + step.id
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(IconButtonStyle())
                .help("Hide this suggestion")
            }
            .padding(Theme.s4)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
            .id(step.id)
            .transition(.opacity)
            .animation(Theme.gentle, value: step.id)
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
    @State private var showsDiff = false

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
                .font(.hkSubhead.monospacedDigit())
                .foregroundStyle(isHovering ? Theme.ink : Theme.ink2)
                .frame(width: Theme.timeColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.figureGap) {
                entryText
                metaLine
            }
        }
        .padding(.horizontal, Theme.rowPaddingH)
        .padding(.vertical, Theme.rowPaddingV)
        .frame(minHeight: Theme.listRow)
        .background(isHovering ? Theme.well : .clear, in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
        .overlay(alignment: .topTrailing) { actionPill.padding(Theme.s2) }
        .contentShape(Rectangle())
        .onTapGesture { if isLong { toggleExpanded() } }
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .contextMenu { menuItems }
        .sheet(isPresented: $showsDiff) {
            HistoryDiffSheet(entry: entry)
                .environment(model)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: expanded ? "Show less" : "Show full text") { if isLong { toggleExpanded() } }
    }

    @ViewBuilder
    private var entryText: some View {
        let text = Text(entry.text)
            .font(.hkBody)
            .lineSpacing(Theme.leading)
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
                Button {
                    showsDiff = true
                } label: {
                    Text("Original recognition")
                        .font(.hkMeta.weight(.medium))
                        .foregroundStyle(Theme.ink2)
                }
                .buttonStyle(.plain)
                .help("Compare with the cleaned-up text")
            } else if let raw = entry.rawText, raw != entry.text {
                Button {
                    showsDiff = true
                } label: {
                    Text("Cleaned")
                        .font(.hkMeta.weight(.medium))
                        .foregroundStyle(Theme.ink2)
                        .underline(true, color: Theme.hairline)
                }
                .buttonStyle(.plain)
                .help("View word diff against original recognition")
            }
            if isRetranscribing {
                ProgressView().controlSize(.mini)
                Text("Re-transcribing…").font(.hkMeta).foregroundStyle(Theme.ink2)
            }
            if isLong {
                Button(action: toggleExpanded) {
                    HStack(spacing: Theme.s0) {
                        Text(expanded ? "Show less" : "Show more")
                        Glyph(.chevronDown, size: Theme.iconXS)
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
        .padding(Theme.s0)
        .background(Theme.sheet, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
        .shadow(color: .black.opacity(0.06), radius: Theme.figureGap, y: Theme.s0)
        .opacity(showsActions ? 1 : 0)
        .offset(x: showsActions ? 0 : Theme.figureGap)
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
            Button("View changes", systemImage: "doc.text.magnifyingglass") {
                showsDiff = true
            }
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
            Glyph(.trash, size: Theme.iconS).foregroundStyle(Theme.ink3)
            Text("Dictation deleted")
                .font(.hkCaption)
                .foregroundStyle(Theme.ink2)
            Spacer()
            Button("Undo") { withAnimation(Theme.gentle) { model.undoDeleteDictation() } }
                .buttonStyle(.plain)
                .font(.hkCaption.weight(.medium))
                .foregroundStyle(Theme.signal)
                .help("Put this dictation back")
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s2)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
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
/// Dictator keeps no audio of past dictations on disk, so this is the "play" Wispr offers.
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
                .font(.hkSubhead)
                .foregroundStyle(Theme.ink2)
                .frame(width: Theme.timeColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.s0) {
                Text("You cancelled a \(cancelled.durationLabel) dictation\(cancelled.appName.map { " in \($0)" } ?? "").")
                    .font(.hkBody)
                    .foregroundStyle(Theme.ink2)
                Text("Kept in memory until you quit Dictator. Nothing was typed or saved.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: Theme.s2)
            Button("Restore to Dictator", icon: .undo) {
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
            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: Theme.hairlineWidth, dash: [4, 3])))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cancelled dictation, \(cancelled.durationLabel)")
    }
}

/// An Apple-grade word diff sheet comparing raw spoken speech against the cleaned transcript.
private struct HistoryDiffSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var entry: DictationHistoryEntry
    @State private var copiedRaw = false

    private var rawText: String {
        entry.cleanedText != nil ? entry.text : (entry.rawText ?? entry.text)
    }

    private var finalText: String {
        entry.cleanedText ?? entry.text
    }

    private struct DiffSegment: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case unchanged, deleted, inserted }
    }

    private var segments: [DiffSegment] {
        let rawTokens = VoiceProfile.tokens(rawText)
        let finalTokens = VoiceProfile.tokens(finalText)
        let gaps = VoiceProfile.gaps(rawTokens.map { $0.lowercased() }, finalTokens.map { $0.lowercased() })

        var result: [DiffSegment] = []
        var rawIdx = 0
        var finalIdx = 0

        for gap in gaps {
            let commonRawEnd = gap.deleted.first ?? rawTokens.count
            let commonFinalEnd = gap.inserted.first ?? finalTokens.count
            while rawIdx < commonRawEnd && finalIdx < commonFinalEnd {
                result.append(DiffSegment(text: finalTokens[finalIdx], kind: .unchanged))
                rawIdx += 1
                finalIdx += 1
            }
            for idx in gap.deleted {
                result.append(DiffSegment(text: rawTokens[idx], kind: .deleted))
            }
            rawIdx = (gap.deleted.last ?? (rawIdx - 1)) + 1
            for idx in gap.inserted {
                result.append(DiffSegment(text: finalTokens[idx], kind: .inserted))
            }
            finalIdx = (gap.inserted.last ?? (finalIdx - 1)) + 1
        }
        while finalIdx < finalTokens.count {
            result.append(DiffSegment(text: finalTokens[finalIdx], kind: .unchanged))
            finalIdx += 1
        }
        return result
    }

    private var diffContent: Text {
        var combined = Text("")
        for (index, segment) in segments.enumerated() {
            let space = index > 0 ? " " : ""
            switch segment.kind {
            case .unchanged:
                combined = combined + Text(space + segment.text).foregroundColor(Theme.ink)
            case .deleted:
                combined = combined + Text(space + segment.text).strikethrough(true, color: Theme.ink3).foregroundColor(Theme.ink3)
            case .inserted:
                combined = combined + Text(space + segment.text).foregroundColor(Theme.signal).bold()
            }
        }
        return combined
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    HStack(spacing: Theme.s2) {
                        Glyph(.sparkle, size: Theme.iconL)
                            .foregroundStyle(Theme.signal)
                        Text("Cleanup changes")
                            .font(.hkCardTitle)
                    }
                    Text("Local rules and Apple Intelligence only ever remove hesitations and format text. Your spoken words are never reworded.")
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.s4)
                Button("Close", icon: .close) { dismiss() }
                    .buttonStyle(IconButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: Theme.s3) {
                ScrollView {
                    diffContent
                        .font(.hkBody)
                        .lineSpacing(Theme.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(Theme.s4)
                }
                .frame(minHeight: Theme.editorShortMax, maxHeight: Theme.editorTall)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))

                HStack(spacing: Theme.s4) {
                    HStack(spacing: Theme.figureGap) {
                        Text("removed").strikethrough(true, color: Theme.ink3).foregroundColor(Theme.ink3).font(.hkCaption)
                        Text("hesitation / stutter").font(.hkCaption).foregroundStyle(Theme.ink2)
                    }
                    HStack(spacing: Theme.figureGap) {
                        Text("adjusted").foregroundColor(Theme.signal).bold().font(.hkCaption)
                        Text("replacement / snap").font(.hkCaption).foregroundStyle(Theme.ink2)
                    }
                    HStack(spacing: Theme.figureGap) {
                        Text("kept").foregroundColor(Theme.ink).font(.hkCaption)
                        Text("spoken text").font(.hkCaption).foregroundStyle(Theme.ink2)
                    }
                }
                .padding(.horizontal, Theme.s1)
            }

            HStack(spacing: Theme.s2) {
                if entry.cleanedText != nil {
                    Button("Redo cleanup", icon: .undo) {
                        model.toggleCleanup(entry)
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else if entry.undoingCleanup() != nil {
                    Button("Undo cleanup", icon: .undo) {
                        model.toggleCleanup(entry)
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button(copiedRaw ? "Copied raw" : "Copy raw", icon: copiedRaw ? .check : .copy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(rawText, forType: .string)
                    copiedRaw = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copiedRaw = false
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(minWidth: Theme.buttonMinWidth)
            }
        }
        .padding(Theme.cardPaddingL)
        .frame(width: Theme.sheetWidth)
        .background(Theme.sheet)
    }
}
