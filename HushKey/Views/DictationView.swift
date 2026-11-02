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
                    NextStepBanner()
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
                Text("Hey \(firstName)")
                    .font(.hkTitle1)
                    .tracking(-0.3)
                HStack(spacing: Theme.s2) {
                    Text(holds ? "Hold" : "Press")
                    KeycapShortcut(label: model.dictationShortcut.label, size: 13)
                    Text(model.dictationShortcut.usesFunctionKey
                         ? "anywhere and talk. Double-tap for hands-free."
                         : holds ? "anywhere and talk. Let go to finish." : "anywhere to start and stop.")
                }
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.finishing)
                        .fixedSize(horizontal: false, vertical: true)
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

    private var problem: String? {
        if let error = model.audio.error ?? model.transcriber.error { return error }
        return model.dictationShortcutNeedsAttention ? model.dictationShortcutStatus : nil
    }

    private var recordButton: some View {
        Button {
            Task { await model.toggleDictation() }
        } label: {
            HStack(spacing: Theme.s2) {
                MorphIcon(phase: morphPhase, level: model.audio.level, lineWidth: 1.8)
                    .frame(width: 16, height: 16)
                Text(isFinishing ? "Transcribing"
                     : model.isStartingDictation ? "Cancel"
                     : model.isStartingSelectedTextEdit ? "Cancel"
                     : model.audio.isRunning ? "Stop" : "Dictate")
                    .contentTransition(.interpolate)
            }
            .frame(minWidth: 96)
        }
        .buttonStyle(PrimaryButtonStyle(tint: model.audio.isRunning ? Theme.ink : Theme.signal))
        .disabled(isFinishing)
        .animation(Theme.snappy, value: model.audio.isRunning)
        .help(model.isStartingDictation ? "Cancel dictation startup"
              : model.audio.isRunning ? "Stop dictation" : "Start dictation")
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
                MorphIcon(phase: morphPhase == .idle ? .done : morphPhase, level: model.audio.level, lineWidth: 2)
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

            if model.audio.isRunning {
                LiveWaveform(level: model.audio.level, isActive: true, barCount: 56, tint: Theme.listening)
                    .frame(height: 28)
                    .transition(.opacity)
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

    private var statsCard: some View {
        let stats = model.dictationStats
        return VStack(alignment: .leading, spacing: Theme.s4) {
            statRow(value: stats.totalWords.formatted(), label: "words dictated")
            statRow(value: stats.wordsPerMinute.map { "\($0)" } ?? "–", label: "words per minute")
            statRow(value: "\(stats.dayStreak)", label: stats.dayStreak == 1 ? "day streak" : "days in a row")
            Rectangle().fill(Theme.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: Theme.s2) {
                SectionLabel(title: "Last 12 weeks")
                ActivityHeatmap(entries: model.dictationHistory)
            }
        }
        .card(padding: Theme.s5)
        .accessibilityElement(children: .combine)
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
                Text("History").font(.hkTitle3)
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

            if model.dictationHistory.isEmpty {
                emptyHistory
            } else if groupedHistory.isEmpty {
                ContentUnavailableView.search(text: historySearch)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .card(style: .outlined)
            } else {
                ForEach(groupedHistory, id: \.day) { group in
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        SectionLabel(title: dayTitle(group.day))
                            .padding(.top, Theme.s2)
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

/// Dark editorial banner that points at the single most useful next step for this user.
private struct NextStepBanner: View {
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
                detail: "Turn on insertion and finished dictations land where your cursor is.",
                action: "Turn on insertion") { model in
                    UserDefaults.standard.set(SettingsView.Section.insertion.rawValue, forKey: "settingsSection")
                    model.screen = .settings
                },
            !model.dictationToneSettings.tones.isEmpty ? nil : Step(
                id: "style", title: "Make it sound like you",
                detail: "Casual in Messages, formal in Mail. Pick a style for each kind of app.",
                action: "Choose styles") { $0.screen = .style },
            !model.dictationTerms.isEmpty || !model.dictationSnippets.isEmpty ? nil : Step(
                id: "vocabulary", title: "Teach HushKey your words",
                detail: "Add names and jargon once. Recognition and spelling follow everywhere.",
                action: "Add words") { $0.screen = .personalization },
            Step(id: "silent", title: "Go quiet with AirPods",
                 detail: "Train a few words or head gestures in the Silent Lab and keep your hands free.",
                 action: "Open Silent Lab") { $0.screen = .setup },
        ].compactMap { $0 }
        return candidates.first { !dismissed.contains($0.id) }
    }

    var body: some View {
        if let step {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .bottom, spacing: Theme.s4) {
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        Text(step.title)
                            .font(.display(28))
                            .tracking(-0.3)
                        Text(step.detail)
                            .font(.hkCallout)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(step.action) { step.perform(model) }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.top, Theme.s2)
                    }
                    Spacer(minLength: 0)
                    BannerWave()
                        .frame(width: 150, height: 80)
                }
                .padding(Theme.s6 - 4)

                Button("Dismiss", systemImage: "xmark") {
                    withAnimation(Theme.gentle) {
                        dismissedRaw = (dismissedRaw.isEmpty ? "" : dismissedRaw + ",") + step.id
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink3)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .padding(Theme.s2)
                .help("Hide this suggestion")
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .background(Theme.signalSoft, in: RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
            .id(step.id)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}

/// Slow ambient waveform drawn in sage; decoration for the banner.
private struct BannerWave: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                let bars = 22
                let gap: CGFloat = 3
                let width = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
                for index in 0..<bars {
                    let t = Double(index) / Double(bars - 1)
                    let envelope = sin(.pi * t)
                    let wave = 0.5 + 0.5 * sin(t * 9 + time * 1.4) * cos(t * 3.1 - time * 0.7)
                    let height = max(width, size.height * envelope * (0.25 + 0.75 * wave))
                    let rect = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2,
                                      width: width, height: height)
                    graphics.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                                  with: .color(Theme.signal.opacity(0.25 + 0.6 * wave)))
                }
            }
        }
        .accessibilityHidden(true)
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
