import SwiftUI

struct DictationView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearHistory = false
    @State private var historySearch = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "VOICE · ON-DEVICE",
                    title: "Dictate anywhere",
                    subtitle: "Speak normally or whisper softly. HushKey transcribes on this Mac, then lets you review, copy, or insert the words into the app you’re using.")

                dictationCard
                Label("On-device recognition · Transcript history stays on this Mac when enabled · Microphone audio is not saved during dictation",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                transcriptCard
                historyCard
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var dictationCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Label("Writing mode", systemImage: model.dictationMode.symbol)
                        .font(.callout.weight(.medium))
                    Picker("Writing mode", selection: Binding(
                        get: { model.dictationMode },
                        set: { model.dictationMode = $0 })) {
                        ForEach(DictationMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(model.audio.isRunning || model.isFinalizingDictation || model.transcriber.isFinalizing)
                    Spacer()
                }
                Text(model.dictationMode == .automatic
                     ? "Automatic selects Natural, Message, Email, or Code from the app that is frontmost when you start with the shortcut."
                     : modeDescription(model.dictationMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.rawDictationText.isEmpty {
                    Label("Last capture: \(model.activeDictationMode.rawValue) · \(model.activeDictationTarget ?? "HushKey window") · \(contextHintSummary)",
                          systemImage: "sparkle.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: model.audio.isRunning ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 42, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(model.audio.isRunning ? Color.red : Color.accentColor)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.isFinalizingDictation ? "Finishing transcription" :
                             model.audio.isRunning ? "Listening" : "Ready when you are")
                            .font(.title3.weight(.semibold))
                        Text(model.isFinalizingDictation
                             ? "HushKey is collecting the final on-device recognition result."
                             : model.audio.isRunning
                             ? "Your speech is being recognized locally. Select Stop when you’re done."
                             : "Your microphone is off until you start a dictation.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if model.audio.isRunning {
                        Circle().fill(.red).frame(width: 9, height: 9)
                        Text("LIVE").font(.caption.weight(.bold)).foregroundStyle(.red)
                    }
                }

                LevelMeter(value: Double(model.audio.level), tint: model.audio.isRunning ? .red : .blue)
                    .frame(height: 10)

                HStack(spacing: 10) {
                    Button {
                        Task { await model.toggleDictation() }
                    } label: {
                        Label(model.isFinalizingDictation ? "Finishing…" :
                              model.audio.isRunning ? "Stop dictation" : "Start dictation",
                              systemImage: model.isFinalizingDictation ? "hourglass" :
                                  model.audio.isRunning ? "stop.fill" : "mic.fill")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.audio.isRunning ? .red : .accentColor)
                    .controlSize(.large)
                    .disabled(model.isFinalizingDictation || model.transcriber.isFinalizing)

                    if model.audio.isRunning {
                        Text(model.audio.activeDeviceName ?? "Default microphone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Shortcut  \(model.dictationShortcut.label)")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                    }
                    Spacer()
                    Button("Microphone settings…") { model.screen = .settings }
                        .buttonStyle(.link)
                }

                if let error = model.audio.error ?? model.transcriber.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(model.dictationShortcutStatus, systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
        }
    }

    private var transcriptCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Transcript").font(.headline)
                    Spacer()
                    if !model.transcriber.text.isEmpty {
                        Button("Clear") { model.clearCurrentDictation() }
                            .disabled(model.audio.isRunning || model.isFinalizingDictation || model.transcriber.isFinalizing)
                    }
                }

                if model.transcriber.isRunning || model.isFinalizingDictation || model.transcriber.isFinalizing {
                    ScrollView {
                        Text(model.isFinalizingDictation || model.transcriber.isFinalizing
                             ? (model.transcriber.text.isEmpty ? "Finishing transcription…" : model.transcriber.text)
                             : (model.transcriber.text.isEmpty ? "Your words will appear here…" : model.transcriber.text))
                            .foregroundStyle(model.transcriber.text.isEmpty ? .tertiary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(minHeight: 140, maxHeight: 220)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    TextEditor(text: transcriptBinding)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 130, maxHeight: 220)
                        .padding(4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topLeading) {
                            if model.transcriber.text.isEmpty {
                                Text("Your transcript will appear here. You can edit it before inserting.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                HStack(spacing: 10) {
                    Button("Copy text", systemImage: "doc.on.doc") { model.copyDictationText() }
                        .disabled(model.audio.isRunning || model.isFinalizingDictation || model.transcriber.isFinalizing ||
                                  model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(model.capturedInsertionTargetName.map { "Insert into \($0)" } ?? "No safe target captured",
                           systemImage: "text.insert") {
                        Task { await model.insertDictationTextIntoCapturedTarget() }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canInsertIntoCapturedTarget || model.audio.isRunning || model.isFinalizingDictation || model.transcriber.isFinalizing ||
                                  model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !model.insertion.isEnabled {
                        Button("Enable insertion…") { model.screen = .settings }
                            .buttonStyle(.link)
                    }
                }

                if model.insertion.isEnabled, model.capturedInsertionTargetName == nil,
                   !model.audio.isRunning, !model.isFinalizingDictation, !model.transcriber.isFinalizing {
                    Label("To enable safe insertion here, start dictation with the global shortcut while the target text field is focused. The target is rechecked before HushKey switches back to it.",
                          systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !model.audio.isRunning, !model.isFinalizingDictation, !model.transcriber.isFinalizing,
                   !model.rawDictationText.isEmpty,
                   model.rawDictationText != model.transcriber.text {
                    Button("Restore original transcript", systemImage: "arrow.uturn.backward") {
                        model.restoreRawTranscript()
                    }
                    .buttonStyle(.link)
                    Text("The original on-device recognition is kept locally so you can recover it after spoken corrections or code formatting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !model.insertion.status.isEmpty {
                    Text(model.insertion.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
        }
    }

    private var historyCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent dictations").font(.headline)
                    Spacer()
                    Button("Clear history…", role: .destructive) { confirmClearHistory = true }
                }
                if let message = model.dictationHistoryMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("Could not") || message.hasPrefix("This transcript")
                                         ? Color.orange : Color.primary.opacity(0.65))
                        .textSelection(.enabled)
                }
                if model.dictationHistory.isEmpty {
                    ContentUnavailableView(
                        "No dictations yet",
                        systemImage: "text.bubble",
                        description: Text(model.savesDictationHistory
                                          ? "Stopped dictations will appear here and stay on this Mac."
                                          : "Transcript history is off. Turn it on in Settings & Data to keep recent text."))
                        .frame(minHeight: 90)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search saved transcripts", text: $historySearch)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Search saved dictations")
                        if !historySearch.isEmpty {
                            Button("Clear search", systemImage: "xmark.circle.fill") { historySearch = "" }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))

                    if filteredHistory.isEmpty {
                        ContentUnavailableView("No matching dictations", systemImage: "magnifyingglass",
                                               description: Text("Try a different search term."))
                            .frame(minHeight: 100)
                    } else {
                        ForEach(filteredHistory) { entry in
                            HStack(spacing: 12) {
                                Button {
                                    model.restoreDictation(entry)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.text).lineLimit(2).foregroundStyle(.primary)
                                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Restore this dictation")

                                if entry.rawText != nil {
                                    Button("Restore raw transcript", systemImage: "arrow.uturn.backward") {
                                        model.restoreDictation(entry, useRawText: true)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .help("Restore the original, unprocessed recognition")
                                }
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                Text("Transcript history is stored in HushKey’s local Application Support folder while history is enabled. Microphone audio is not saved by dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .confirmationDialog("Delete all recent dictations?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) { model.clearDictationHistory() }
        }
    }

    private var filteredHistory: [DictationHistoryEntry] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.dictationHistory }
        return model.dictationHistory.filter { entry in
            entry.text.localizedCaseInsensitiveContains(query) ||
                (entry.rawText?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { model.transcriber.text }, set: { model.editCurrentDictation($0) })
    }

    private func modeDescription(_ mode: DictationMode) -> String {
        switch mode {
        case .automatic: "HushKey selects a writing style from the app in front."
        case .natural: "Keeps the on-device transcript with your vocabulary, snippets, and optional spoken corrections."
        case .message: "Adds common message terms as local recognition hints and turns “new line” into a line break."
        case .email: "Adds email terms as local recognition hints; “new paragraph” starts a new paragraph."
        case .code: "Formats spoken programming tokens such as parentheses, underscores, arrows, and new lines."
        }
    }

    private var contextHintSummary: String {
        guard model.usesNearbyTextHints else { return "nearby hints off" }
        return model.usedNearbyTextHints ? "nearby terms used" : "no nearby terms available"
    }
}
