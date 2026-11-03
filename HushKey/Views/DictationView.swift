import SwiftUI

struct DictationView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearHistory = false
    @State private var historySearch = ""
    @State private var searching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                header
                HStack(alignment: .top, spacing: Theme.s4) {
                    HeroCard()
                    statsCard.frame(width: 248)
                }
                .fixedSize(horizontal: false, vertical: true)
                if showsComposer {
                    composer
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                removal: .opacity))
                }
                historySection
            }
            .pageLayout(maxWidth: Theme.homeWidth)
            .animation(Theme.gentle, value: showsComposer)
        }
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
                HStack(alignment: .center, spacing: Theme.s2) {
                    Text("Hey \(firstName), \(holds ? "hold" : "press")")
                    KeycapShortcut(label: model.dictationShortcut.label, size: 17)
                    Text(holds ? "and just talk" : "to dictate")
                }
                .font(.hkTitle1)
                .tracking(-0.3)
                .accessibilityElement(children: .combine)
                Text(model.dictationShortcut.usesFunctionKey
                     ? "Works in any app. Double-tap for hands-free. A whisper is enough."
                     : holds ? "Works in any app. Let go to finish. A whisper is enough."
                     : "Works in any app. Press again to finish. A whisper is enough.")
                    .font(.hkCallout)
                    .foregroundStyle(Theme.ink2)
                if let problem {
                    HStack(spacing: Theme.s2) {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
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
                }
            }
            Spacer(minLength: Theme.s4)
            recordButton
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
                    .frame(width: 16, height: 16)
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
                    StatusChip(title: target, systemImage: "macwindow")
                        .help("Dictated from \(target) · \(contextHintSummary)")
                }
                Spacer(minLength: Theme.s2)
                if hasText, !isBusy {
                    Button("Clear", systemImage: "xmark") { model.clearCurrentDictation() }
                        .buttonStyle(IconButtonStyle())
                        .help("Clear the current transcript")
                }
            }

            transcriptEditor

            HStack(spacing: Theme.s2) {
                Button("Insert", systemImage: "text.insert") { model.insertDictationText() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.insertion.isEnabled || isBusy || !hasText)
                    .help(model.insertion.isEnabled ? "Insert into the app you dictated from" : "Turn on insertion in Settings")
                Button("Copy", systemImage: "doc.on.doc") { model.copyDictationText() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isBusy || !hasText)
                if !isBusy, !model.rawDictationText.isEmpty, model.rawDictationText != model.transcriber.text {
                    Button("Original", systemImage: "arrow.uturn.backward") { model.restoreRawTranscript() }
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
            Label(model.dictationMode.rawValue, systemImage: model.dictationMode.symbol)
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

    /// Lifetime numbers from the same ledger as Insights, so the two always agree.
    private var statsCard: some View {
        let ledger = model.usageLedger
        let streak = ledger.currentStreak()
        return Button {
            model.screen = .insights
        } label: {
            VStack(alignment: .leading, spacing: Theme.s4) {
                statRow(value: ledger.totalWords.formatted(), label: ledger.totalWords == 1 ? "word dictated" : "words dictated")
                statRow(value: ledger.wordsPerMinute.map { "\($0)" } ?? "–", label: "words per minute")
                statRow(value: "\(streak)", label: "day streak")
                Rectangle().fill(Theme.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: Theme.s2) {
                    HStack {
                        SectionLabel(title: "Last 12 weeks")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
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

    private func statRow(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
            Text(value)
                .font(.display(28))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Theme.gentle, value: value)
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
                        Button("Search", systemImage: "magnifyingglass") { searching = true }
                            .buttonStyle(IconButtonStyle())
                            .help("Search history")
                    }
                }
                if !model.dictationHistory.isEmpty || model.dictationHistoryArchiveUnreadable {
                    Menu {
                        Button(!model.dictationHistoryArchiveUnreadable ? "Delete all history…" : "Remove unreadable archive…",
                               role: .destructive) { confirmClearHistory = true }
                    } label: {
                        Image(systemName: "ellipsis")
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
                                HistoryRow(entry: entry, isLocked: isBusy)
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
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3)
            TextField("Search history", text: $historySearch)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .accessibilityLabel("Search saved dictations")
                .onExitCommand {
                    historySearch = ""
                    searching = false
                }
            Button("Close search", systemImage: "xmark.circle.fill") {
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
                Button("Dismiss", systemImage: "xmark") {
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

/// One saved dictation: time column, text, and actions that appear on hover.
private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    var entry: DictationHistoryEntry
    var isLocked: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s4) {
            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(Theme.ink2)
                .frame(width: 82, alignment: .leading)
            Text(entry.text)
                .font(.hkBody)
                .lineSpacing(3)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            HStack(spacing: 0) {
                action("Copy", "doc.on.doc") { model.copyDictation(entry) }
                action("Edit again", "square.and.pencil") { model.restoreDictation(entry) }
                    .disabled(isLocked)
                if entry.rawText != nil {
                    action("Restore original recognition", "arrow.uturn.backward") {
                        model.restoreDictation(entry, useRawText: true)
                    }
                    .disabled(isLocked)
                }
                action("Delete", "trash") {
                    withAnimation(Theme.gentle) { model.deleteDictation(entry) }
                }
            }
            .opacity(isHovering ? 1 : 0)
            .offset(x: isHovering ? 0 : 6)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, 15)
        .frame(minHeight: Theme.listRow)
        .background(isHovering ? Theme.well : .clear)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering } }
        .contextMenu {
            Button("Copy") { model.copyDictation(entry) }
            Button("Edit again") { model.restoreDictation(entry) }.disabled(isLocked)
            if entry.rawText != nil {
                Button("Restore original recognition") { model.restoreDictation(entry, useRawText: true) }.disabled(isLocked)
            }
            Divider()
            Button("Delete", role: .destructive) { model.deleteDictation(entry) }
        }
        .accessibilityElement(children: .contain)
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: perform)
            .buttonStyle(IconButtonStyle())
            .help(title)
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
            Button("Recover", systemImage: "arrow.uturn.backward") {
                Task { await model.recoverCancelledDictation() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isLocked)
            .help("Transcribe it on this Mac and add it to History")
            Button("Discard", systemImage: "xmark") { withAnimation(Theme.snappy) { model.discardCancelledDictation() } }
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
