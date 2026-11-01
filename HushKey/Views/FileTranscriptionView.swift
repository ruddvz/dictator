import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedURL: URL?
    @State private var exportMessage: String?
    @State private var historySearch = ""
    @State private var activeSessionID: UUID?
    @State private var activeSourceName: String?
    @State private var activeLanguageIdentifier = ""
    @State private var activeModelVariant: String?
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var confirmClearHistory = false
    @State private var engine: FileTranscriptionEngine = .apple

    private var transcription: LocalFileTranscriber { model.fileTranscriber }
    private var whisper: WhisperKitFileTranscriber { model.whisperFileTranscriber }
    private var historySessions: [FileTranscriptionSession] { model.fileTranscriptionSessions }
    private var isBusy: Bool { transcription.isTranscribing || whisper.isTranscribing || whisper.isDownloading }
    private var currentText: String { engine == .apple ? transcription.text : whisper.text }
    private var currentCues: [SubtitleCue] { engine == .apple ? transcription.cues : whisper.cues }
    private var currentStatus: String? { engine == .apple ? transcription.status : whisper.status }
    private var currentError: String? { engine == .apple ? transcription.error : whisper.error }
    private var filteredSessions: [FileTranscriptionSession] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return historySessions }
        return historySessions.filter {
            $0.sourceName.localizedCaseInsensitiveContains(query) ||
                $0.text.localizedCaseInsensitiveContains(query) ||
                $0.engine.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        @Bindable var whisper = model.whisperFileTranscriber
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "LOCAL AUDIO",
                    title: "Transcribe a file",
                    subtitle: "Choose an audio file to create a transcript and timestamped subtitles on this Mac.")

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Local engine", selection: $engine) {
                            ForEach(FileTranscriptionEngine.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 380)
                        .disabled(isBusy || !currentText.isEmpty)

                        if !currentText.isEmpty {
                            Label("This transcript is saved in Recent file transcripts. Choose an audio file to start a separate job or switch engines.",
                                  systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Label(engine == .apple
                              ? "Apple Speech runs on this Mac when the selected language supports on-device recognition. No speech model download is needed."
                              : "WhisperKit uses a model you choose and download. The model download needs internet; transcription itself runs locally after setup.",
                              systemImage: "lock.shield")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if engine == .whisperKit {
                            HStack(spacing: 12) {
                                Picker("WhisperKit model", selection: $whisper.selectedVariant) {
                                    ForEach(WhisperModelVariant.allCases) { variant in
                                        Text(variant.title).tag(variant)
                                    }
                                }
                                .frame(maxWidth: 360)
                                .disabled(isBusy)
                                if whisper.selectedModelIsDownloaded {
                                    Label("On this Mac", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                    Button("Remove model", role: .destructive) { whisper.removeSelectedModel() }
                                        .disabled(isBusy)
                                } else {
                                    Button("Download model", systemImage: "arrow.down.circle") {
                                        whisper.downloadSelectedModel()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isBusy)
                                }
                            }
                            if whisper.isDownloading {
                                HStack(spacing: 12) {
                                    ProgressView(value: whisper.downloadProgress)
                                        .accessibilityLabel("Downloading local speech model")
                                    Text(whisper.downloadProgressDescription)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Button("Cancel", role: .cancel) { whisper.cancelDownload() }
                                        .disabled(whisper.status == "Cancelling model download…")
                                }
                                Text("Model files stay in HushKey’s local Application Support folder. You can remove them here.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Choose audio file…", systemImage: "folder") { chooseFile() }
                                .disabled(isBusy)
                            if let sourceName = selectedURL?.lastPathComponent ?? activeSourceName {
                                Label(sourceName, systemImage: "waveform")
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Button(action: startTranscription) {
                                Label(isBusy ? "Working…" : "Transcribe locally",
                                      systemImage: isBusy ? "hourglass" : "waveform")
                                    .frame(minWidth: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedURL == nil || isBusy ||
                                      (engine == .whisperKit && !whisper.selectedModelIsDownloaded))

                            if engine == .apple && transcription.isTranscribing {
                                Button("Cancel", role: .cancel) { transcription.cancel() }
                            } else if engine == .whisperKit && whisper.isTranscribing {
                                Button("Cancel", role: .cancel) { whisper.cancelTranscription() }
                                    .disabled(whisper.status == "Cancelling transcription…")
                            }
                            Spacer()
                            if engine == .apple {
                                Picker("Language", selection: Binding(get: { model.dictationLanguage },
                                                                      set: { model.dictationLanguage = $0 })) {
                                    ForEach(DictationLanguage.onDevice) { language in
                                        Text(language.name).tag(language.identifier)
                                    }
                                }
                                .frame(maxWidth: 260)
                                .disabled(isBusy)
                            } else {
                                Picker("Language", selection: $whisper.selectedLanguage) {
                                    ForEach(WhisperKitLanguage.options) { language in
                                        Text(language.name).tag(language.identifier)
                                    }
                                }
                                .frame(maxWidth: 260)
                                .disabled(isBusy)
                            }
                        }

                        if let error = currentError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let status = currentStatus {
                            Label(status, systemImage: isBusy ? "gearshape.2" : "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                }

                recentSessionsCard

                GroupBox("Transcript") {
                    VStack(alignment: .leading, spacing: 12) {
                        if currentText.isEmpty {
                            ContentUnavailableView("No transcript yet", systemImage: "text.alignleft",
                                                   description: Text("Choose an audio file to begin."))
                                .frame(minHeight: 160)
                        } else {
                            TextEditor(text: transcriptBinding)
                                .font(.body)
                                .frame(minHeight: 220)
                                .disabled(isBusy)
                                .padding(4)
                                .background(.background, in: RoundedRectangle(cornerRadius: 8))

                            HStack(spacing: 10) {
                                Button("Save text…", systemImage: "doc.text") { save(content: currentText, fileExtension: "txt", type: .plainText) }
                                Button("Export SRT…", systemImage: "captions.bubble") { save(content: SubtitleFormatter.srt(currentCues), fileExtension: "srt", type: UTType(filenameExtension: "srt") ?? .plainText) }
                                    .disabled(currentCues.isEmpty)
                                Button("Export WebVTT…", systemImage: "captions.bubble") { save(content: SubtitleFormatter.vtt(currentCues), fileExtension: "vtt", type: UTType(filenameExtension: "vtt") ?? .plainText) }
                                    .disabled(currentCues.isEmpty)
                                Spacer()
                                Text("\(currentCues.count) timed segments")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Transcript edits save automatically to Recent file transcripts and appear in TXT export. Subtitle exports keep the original timed recognition segments.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let exportMessage {
                            Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if activeSessionID == nil, !isBusy, selectedURL == nil, let latest = historySessions.first {
                restore(latest)
            }
        }
        .onChange(of: model.fileTranscriptionSessions.first?.id) { _, _ in
            if activeSessionID == nil, !isBusy, selectedURL == nil, let latest = historySessions.first {
                restore(latest)
            }
        }
        .onChange(of: currentText) { _, _ in scheduleSessionSave() }
        .onDisappear {
            pendingSaveTask?.cancel()
            persistActiveSession()
        }
        .confirmationDialog("Delete all saved file transcripts?", isPresented: $confirmClearHistory,
                            titleVisibility: .visible) {
            Button("Delete transcripts", role: .destructive) { clearHistory() }
        } message: {
            Text("This removes HushKey’s saved transcript text and subtitle cues from this Mac. Original audio files are not stored here.")
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { currentText }, set: { engine == .apple ? transcription.replaceText($0) : whisper.replaceText($0) })
    }

    private var recentSessionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Search file transcripts", text: $historySearch)
                        .textFieldStyle(.roundedBorder)
                    if !historySessions.isEmpty {
                        Button("Delete all…", role: .destructive) { confirmClearHistory = true }
                            .buttonStyle(.bordered)
                    }
                }

                if filteredSessions.isEmpty {
                    ContentUnavailableView(
                        historySearch.isEmpty ? "No saved file transcripts" : "No matching transcripts",
                        systemImage: historySearch.isEmpty ? "waveform" : "magnifyingglass",
                        description: Text(historySearch.isEmpty
                                          ? "Finished and edited file transcripts are saved on this Mac so you can return to them."
                                          : "Search by file name or words in the transcript."))
                        .frame(minHeight: 100)
                } else {
                    ForEach(filteredSessions) { session in
                        HStack(spacing: 10) {
                            Button { restore(session) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(session.sourceName).font(.headline).lineLimit(1)
                                        Text(session.engine.rawValue).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(session.text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                    Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Restore this file transcript")

                            Button("Delete \(session.sourceName)", systemImage: "trash", role: .destructive) {
                                delete(session)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                }

                Text("Transcript text and timed cues stay on this Mac. HushKey does not copy or retain the source audio.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = model.fileTranscriptionHistoryMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(8)
        } label: {
            Label("Recent file transcripts · \(historySessions.count)", systemImage: "clock.arrow.circlepath")
        }
    }

    private func startTranscription() {
        guard let selectedURL else { return }
        pendingSaveTask?.cancel()
        let sessionID = UUID()
        activeSessionID = sessionID
        activeSourceName = selectedURL.lastPathComponent
        activeLanguageIdentifier = engine == .apple ? model.dictationLanguage : whisper.selectedLanguage
        activeModelVariant = engine == .whisperKit ? whisper.selectedVariant.rawValue : nil
        let languageIdentifier = activeLanguageIdentifier
        exportMessage = nil

        if engine == .apple {
            Task {
                await transcription.transcribe(file: selectedURL, localeIdentifier: languageIdentifier,
                                               sessionID: sessionID)
                persistActiveSession()
            }
        } else {
            whisper.transcribe(file: selectedURL, languageIdentifier: languageIdentifier,
                               sessionID: sessionID)
        }
    }

    private func scheduleSessionSave() {
        guard !isBusy, activeSessionID != nil else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistActiveSession()
        }
    }

    private func persistActiveSession() {
        pendingSaveTask?.cancel()
        guard let activeSessionID, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let session = FileTranscriptionSession(
            id: activeSessionID,
            sourceName: selectedURL?.lastPathComponent ?? activeSourceName ?? "Audio transcript",
            engine: engine,
            languageIdentifier: activeLanguageIdentifier,
            modelVariant: activeModelVariant,
            text: currentText,
            cues: currentCues)
        model.saveFileTranscriptionSession(session)
    }

    private func restore(_ session: FileTranscriptionSession) {
        guard !isBusy else { return }
        pendingSaveTask?.cancel()
        engine = session.engine
        selectedURL = nil
        activeSessionID = session.id
        activeSourceName = session.sourceName
        activeLanguageIdentifier = session.languageIdentifier
        activeModelVariant = session.modelVariant
        exportMessage = "Restored saved transcript. The original audio file is not stored by HushKey."
        if session.engine == .apple {
            transcription.restore(session)
        } else {
            whisper.restore(session)
        }
    }

    private func delete(_ session: FileTranscriptionSession) {
        if activeSessionID == session.id { activeSessionID = nil }
        model.deleteFileTranscriptionSession(session)
    }

    private func clearHistory() {
        model.clearFileTranscriptionHistory()
        activeSessionID = nil
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose Audio"
        if panel.runModal() == .OK, let url = panel.url {
            persistActiveSession()
            pendingSaveTask?.cancel()
            selectedURL = url
            activeSessionID = nil
            activeSourceName = nil
            exportMessage = nil
            transcription.clear()
            whisper.clear()
        }
    }

    private func save(content: String, fileExtension: String, type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let sourceName = selectedURL?.lastPathComponent ?? activeSourceName ?? "HushKey-transcript"
        let sourceStem = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = sourceStem + ".\(fileExtension)"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(content.utf8).write(to: url, options: .atomic)
            exportMessage = "Saved \(url.lastPathComponent)."
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
