import SwiftUI

struct DictationView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearHistory = false
    @State private var historySearch = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                HStack(alignment: .top, spacing: 18) {
                    nowCard
                    VStack(spacing: 14) {
                        statsCard
                        privacyCard
                    }
                    .frame(width: 230)
                }
                historySection
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .confirmationDialog("Delete all recent dictations?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) { model.clearDictationHistory() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(model.dictationCaptureBehavior == .hold ? "Hold" : "Press")
                KeycapShortcut(label: model.dictationShortcut.label, size: 15)
                Text("to dictate anywhere")
            }
            .font(.system(size: 26, weight: .semibold))
            let error = model.audio.error ?? model.transcriber.error
            Text(error ?? shortcutHint)
                .font(.callout)
                .foregroundStyle(error == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var shortcutHint: String {
        model.dictationShortcutStatus.hasPrefix("Could not")
            ? model.dictationShortcutStatus
            : "Speak normally or whisper. Text is recognized on this Mac, then you review, copy, or insert it."
    }

    // MARK: Now card

    private var isBusy: Bool {
        model.audio.isRunning || model.isFinalizingDictation || model.transcriber.isFinalizing
    }

    private var isFinishing: Bool { model.isFinalizingDictation || model.transcriber.isFinalizing }

    private var hasText: Bool {
        !model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                statusLabel
                modeMenu
                if !model.rawDictationText.isEmpty, let target = model.activeDictationTarget {
                    StatusChip(title: target, systemImage: "macwindow")
                        .help("Last capture went to \(target) · \(contextHintSummary)")
                }
                Spacer(minLength: 8)
                recordButton
            }

            if model.audio.isRunning {
                LiveWaveform(level: model.audio.level, isActive: true, barCount: 48, tint: Theme.listening)
                    .frame(height: 26)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            transcriptEditor

            HStack(spacing: 8) {
                Button("Copy", systemImage: "doc.on.doc") { model.copyDictationText() }
                    .disabled(isBusy || !hasText)
                Button("Insert", systemImage: "text.insert") { model.insertDictationText() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.insertion.isEnabled || isBusy || !hasText)
                    .help(model.insertion.isEnabled ? "Insert into the app you dictated from" : "Turn on insertion in Settings & Data")
                if !isBusy, !model.rawDictationText.isEmpty, model.rawDictationText != model.transcriber.text {
                    Button("Original", systemImage: "arrow.uturn.backward") { model.restoreRawTranscript() }
                        .help("Restore the unprocessed on-device recognition")
                }
                Spacer()
                if !model.insertion.isEnabled {
                    Button("Enable insertion…") { model.screen = .settings }
                        .buttonStyle(.link)
                        .font(.callout)
                }
                if hasText {
                    Button("Clear", systemImage: "xmark") { model.clearCurrentDictation() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(isBusy)
                        .help("Clear the current transcript")
                }
            }
            .controlSize(.regular)

            if !model.insertion.status.isEmpty {
                Text(model.insertion.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .card(padding: 18)
        .animation(.easeOut(duration: 0.18), value: model.audio.isRunning)
    }

    private var statusLabel: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.audio.isRunning ? Theme.listening : isFinishing ? Theme.finishing : Color.green)
                .frame(width: 8, height: 8)
            Text(model.audio.isRunning ? "Listening" : isFinishing ? "Transcribing" : "Ready")
                .font(.headline)
        }
        .accessibilityElement(children: .combine)
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
                .font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.7), in: Capsule())
        .disabled(isBusy)
        .help(modeDescription(model.dictationMode))
    }

    private var recordButton: some View {
        Button {
            Task { await model.toggleDictation() }
        } label: {
            Label(isFinishing ? "Finishing" : model.audio.isRunning ? "Stop" : "Start",
                  systemImage: isFinishing ? "hourglass" : model.audio.isRunning ? "stop.fill" : "mic.fill")
                .frame(minWidth: 84)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(model.audio.isRunning ? Theme.listening : .accentColor)
        .controlSize(.large)
        .disabled(isFinishing)
        .help(model.audio.isRunning ? "Stop dictation" : "Start dictation")
    }

    @ViewBuilder
    private var transcriptEditor: some View {
        if isBusy {
            ScrollView {
                Text(model.transcriber.text.isEmpty
                     ? (isFinishing ? "Finishing transcription…" : "Listening… your words appear here")
                     : model.transcriber.text)
                    .font(.title3)
                    .foregroundStyle(model.transcriber.text.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 120, maxHeight: 240)
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            TextEditor(text: transcriptBinding)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 120, maxHeight: 240)
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if model.transcriber.text.isEmpty {
                        Text("Your words appear here to edit before you copy or insert them.")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: Side cards

    private var statsCard: some View {
        let stats = model.dictationStats
        return VStack(alignment: .leading, spacing: 12) {
            statRow(value: stats.totalWords.formatted(), label: "total words")
            statRow(value: stats.wordsPerMinute.map { "\($0)" } ?? "—", label: "wpm")
            statRow(value: "\(stats.dayStreak)", label: "day streak")
            statRow(value: "\(stats.dictations)", label: stats.dictations == 1 ? "dictation" : "dictations")
        }
        .card(padding: 18)
        .accessibilityElement(children: .combine)
    }

    private func statRow(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: 26, weight: .medium, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Stays on this Mac", systemImage: "lock.shield")
                .font(.callout.weight(.semibold))
            Text(model.savesDictationHistory
                 ? "Recognition runs on-device. Audio isn’t saved; text history is kept locally."
                 : "Recognition runs on-device. Audio and history aren’t saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 14)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("History").font(.title3.weight(.semibold))
                Spacer()
                if !model.dictationHistory.isEmpty {
                    searchField
                    Menu {
                        Button("Delete all history…", role: .destructive) { confirmClearHistory = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("History options")
                }
            }

            if let message = model.dictationHistoryMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("Could not") || message.hasPrefix("This transcript")
                                     ? Color.orange : Color.secondary)
                    .textSelection(.enabled)
            }

            if model.dictationHistory.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "text.bubble",
                    description: Text(model.savesDictationHistory
                                      ? "Finished dictations appear here, grouped by day."
                                      : "History is off. Turn it on in Settings & Data to keep recent text."))
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .card()
            } else if groupedHistory.isEmpty {
                ContentUnavailableView.search(text: historySearch)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .card()
            } else {
                ForEach(groupedHistory, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dayTitle(group.day).uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 86) }
                                HistoryRow(entry: entry, isLocked: isBusy)
                            }
                        }
                        .card(padding: 0)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $historySearch)
                .textFieldStyle(.plain)
                .frame(width: 160)
                .accessibilityLabel("Search saved dictations")
            if !historySearch.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { historySearch = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: Capsule())
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
        Binding(get: { model.transcriber.text }, set: { model.transcriber.replaceText($0) })
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

/// One saved dictation: time column, text, and actions that appear on hover.
private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    var entry: DictationHistoryEntry
    var isLocked: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(entry.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            HStack(spacing: 2) {
                action("Copy", "doc.on.doc") { model.copyDictation(entry) }
                action("Edit again", "square.and.pencil") { model.restoreDictation(entry) }
                    .disabled(isLocked)
                if entry.rawText != nil {
                    action("Restore original recognition", "arrow.uturn.backward") {
                        model.restoreDictation(entry, useRawText: true)
                    }
                    .disabled(isLocked)
                }
                action("Delete", "trash") { model.deleteDictation(entry) }
            }
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 24, height: 22)
            .help(title)
    }
}
