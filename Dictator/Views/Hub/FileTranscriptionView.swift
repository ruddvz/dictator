import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @Environment(AppModel.self) private var model
    @State private var exportMessage: String?
    @State private var historySearch = ""
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var confirmClearHistory = false
    @State private var isDropTargeted = false

    private var workspace: FileTranscriptionWorkspace { model.fileTranscriptionWorkspace }
    private var transcription: LocalFileTranscriber { model.fileTranscriber }
    private var whisper: WhisperKitFileTranscriber { model.whisperFileTranscriber }
    private var historySessions: [FileTranscriptionSession] { model.fileTranscriptionSessions }
    private var parakeet: ParakeetFileTranscriber { model.parakeetFileTranscriber }
    private var isBusy: Bool {
        transcription.isTranscribing || whisper.isTranscribing || whisper.isDownloading || parakeet.isTranscribing
    }
    private var currentText: String {
        switch workspace.engine { case .parakeet: parakeet.text; case .apple: transcription.text; case .whisperKit: whisper.text }
    }
    private var currentCues: [SubtitleCue] {
        switch workspace.engine { case .parakeet: parakeet.cues; case .apple: transcription.cues; case .whisperKit: whisper.cues }
    }
    private var currentStatus: String? {
        switch workspace.engine { case .parakeet: parakeet.status; case .apple: transcription.status; case .whisperKit: whisper.status }
    }
    private var currentError: String? {
        switch workspace.engine { case .parakeet: parakeet.error; case .apple: transcription.error; case .whisperKit: whisper.error }
    }
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
            PageColumn {
                PageHeader(title: "Files",
                           subtitle: "Turn a recording into text and subtitles, on this Mac.") {
                    // The source card offers "Choose file…" until a file is picked.
                    if workspace.selectedURL != nil {
                        Button("Choose another…", icon: .folder) { chooseFile() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(isBusy)
                    }
                }

                sourceCard

                SettingsGroup(title: "Engine") {
                    SettingsRow(title: "Speech engine",
                                detail: !currentText.isEmpty && !isBusy ? "Clear the transcript to change engine."
                                    : workspace.engine == .parakeet
                                        ? (model.parakeet.isDownloaded
                                           ? "Parakeet, the same engine as dictation. English only, text without subtitle timing."
                                           : "Parakeet isn’t on this Mac yet. Download it in Settings → Dictation.")
                                    : workspace.engine == .apple ? "Apple Speech. Nothing to download."
                                    : "WhisperKit. Downloads a model once, then runs offline.") {
                        MenuPicker(selection: Binding(get: { workspace.engine },
                                                     set: { workspace.engine = $0 }),
                                   options: FileTranscriptionEngine.allCases.map { ($0, $0.rawValue) })
                            .disabled(isBusy || !currentText.isEmpty)
                    }
                    SettingsRow(title: "Language", detail: nil) {
                        if workspace.engine == .parakeet {
                            Text("English").font(.hkBody).foregroundStyle(Theme.ink2)
                        } else if workspace.engine == .apple {
                            LanguageButton(selection: Binding(get: { model.dictationLanguage },
                                                              set: { model.dictationLanguage = $0 }))
                                .disabled(isBusy)
                        } else {
                            MenuPicker(selection: $whisper.selectedLanguage,
                                       options: WhisperKitLanguage.options.map { ($0.identifier, $0.name) })
                                .disabled(isBusy)
                        }
                    }
                    if workspace.engine == .whisperKit {
                        SettingsRow(title: "Model",
                                    detail: whisper.selectedModelIsDownloaded ? "On this Mac." : "Not downloaded yet.") {
                            HStack(spacing: Theme.s2) {
                                if whisper.selectedModelIsDownloaded {
                                    Button("Remove") { whisper.removeSelectedModel() }
                                        .buttonStyle(DestructiveButtonStyle())
                                        .disabled(isBusy)
                                } else if !whisper.isDownloading {
                                    Button("Download") { whisper.downloadSelectedModel() }
                                        .buttonStyle(PrimaryButtonStyle())
                                        .disabled(isBusy)
                                }
                                MenuPicker(selection: $whisper.selectedVariant,
                                           options: WhisperModelVariant.allCases.map { ($0, $0.title) })
                                    .disabled(isBusy)
                            }
                        }
                        if whisper.isDownloading {
                            GroupRow {
                                HStack(spacing: Theme.s3) {
                                    ProgressView(value: whisper.downloadProgress)
                                        .tint(Theme.signal)
                                        .accessibilityLabel("Downloading local speech model")
                                    Text(whisper.downloadProgressDescription)
                                        .font(.hkCaption.monospacedDigit())
                                        .foregroundStyle(Theme.ink2)
                                    Button("Cancel") { whisper.cancelDownload() }
                                        .buttonStyle(SecondaryButtonStyle())
                                        .disabled(whisper.status == "Cancelling model download…")
                                }
                            }
                        }
                    }
                }

                if !currentText.isEmpty { transcriptCard }

                recentSessionsCard
            }
        }
        .onAppear {
            if workspace.engine == .parakeet, !model.parakeet.isDownloaded, currentText.isEmpty, !isBusy {
                workspace.engine = .apple
            }
            if workspace.shouldRestoreLatest(isBusy: isBusy), let latest = historySessions.first {
                restore(latest)
            }
        }
        .onChange(of: model.fileTranscriptionSessions.first?.id) { _, _ in
            if workspace.shouldRestoreLatest(isBusy: isBusy), let latest = historySessions.first {
                restore(latest)
            }
        }
        .onChange(of: currentText) { _, _ in scheduleSessionSave() }
        .onDisappear {
            pendingSaveTask?.cancel()
            persistActiveSession()
        }
        .confirmationDialog(!model.fileTranscriptionHistoryArchiveUnreadable
                            ? "Delete all saved file transcripts?" : "Remove unreadable transcript archive?",
                            isPresented: $confirmClearHistory,
                            titleVisibility: .visible) {
            Button(!model.fileTranscriptionHistoryArchiveUnreadable ? "Delete transcripts" : "Remove archive",
                   role: .destructive) { clearHistory() }
        } message: {
            if let recoveryCopyURL = model.fileTranscriptionHistoryRecoveryCopyURL {
                Text("Dictator kept a recovery copy at \(recoveryCopyURL.path). Removing the unreadable file lets new transcripts save normally.")
            } else if model.fileTranscriptionHistoryArchiveUnreadable {
                Text("Dictator could not make a recovery copy. The original file remains in place until you remove it.")
            } else {
                Text("This removes Dictator’s saved transcript text and subtitle cues from this Mac. Original audio files are not stored here. Any transcription already running can still be exported, but will not be added back to history.")
            }
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { currentText }, set: {
            switch workspace.engine {
            case .parakeet: parakeet.replaceText($0)
            case .apple: transcription.replaceText($0)
            case .whisperKit: whisper.replaceText($0)
            }
        })
    }

    /// The page's signature: a generous dashed sage drop zone holding the file and its one
    /// action. It fills with a sage tint only while a file is held over it.
    private var sourceCard: some View {
        @Bindable var whisper = model.whisperFileTranscriber
        let sourceName = workspace.selectedURL?.lastPathComponent ?? workspace.activeSourceName
        return HStack(spacing: Theme.s4) {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text(sourceName ?? "Drop audio or video here")
                    .font(.hkTitle2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Group {
                    if let error = currentError {
                        Label(error, icon: .warning)
                            .font(.hkCallout)
                            .foregroundStyle(Theme.danger)
                    } else if let status = currentStatus {
                        Text(status)
                            .font(.hkCallout)
                            .foregroundStyle(Theme.ink2)
                    } else {
                        Text("M4A, MP3, WAV, MOV and more. Audio is never kept.")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .lineLimit(2)
            }
            Spacer(minLength: Theme.s4)
            if workspace.engine == .apple && transcription.isTranscribing {
                Button("Cancel") { transcription.cancel() }
                    .buttonStyle(SecondaryButtonStyle())
            } else if workspace.engine == .parakeet && parakeet.isTranscribing {
                Button("Cancel") { parakeet.cancel() }
                    .buttonStyle(SecondaryButtonStyle())
            } else if workspace.engine == .whisperKit && whisper.isTranscribing {
                Button("Cancel") { whisper.cancelTranscription() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(whisper.status == "Cancelling transcription…")
            }
            if workspace.selectedURL == nil && !isBusy {
                Button("Choose file…") { chooseFile() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(action: startTranscription) {
                    Label(isBusy ? "Working…" : "Transcribe", icon: isBusy ? .clock : .waveform)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(workspace.selectedURL == nil || isBusy ||
                          (workspace.engine == .whisperKit && !whisper.selectedModelIsDownloaded) ||
                          (workspace.engine == .parakeet && !model.parakeet.isDownloaded))
            }
        }
        .padding(.horizontal, Theme.cardPaddingL)
        .padding(.vertical, Theme.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isDropTargeted ? Theme.signalSoft : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(isDropTargeted ? Theme.signal : Theme.signalEdge,
                          style: StrokeStyle(lineWidth: Theme.selectedStroke, dash: Theme.dash)))
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        .contentShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .dropDestination(for: URL.self) { urls, _ in
            guard !isBusy, let url = urls.first, url.isFileURL else { return false }
            selectFile(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private var transcriptCard: some View {
        PageSection("Transcript") {
            Text(workspace.engine == .parakeet ? "No subtitle timing with Parakeet" : "\(currentCues.count) timed segments")
                .font(.hkMeta.monospacedDigit())
                .foregroundStyle(Theme.ink3)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: transcriptBinding)
                    .font(.hkBody)
                    .lineSpacing(Theme.leading)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: Theme.editorTall)
                    .disabled(isBusy)
                    .padding(Theme.s3)
                    .accessibilityLabel("File transcript")
                    .accessibilityHint("Edit the transcript. Subtitle exports keep the original wording and timing; Save text includes your edits.")
                RowDivider()
                HStack(spacing: Theme.s2) {
                    Text(exportMessage ?? "Subtitle exports keep original wording and timing. Save text includes edits.")
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("SRT") { save(content: SubtitleFormatter.srt(currentCues), fileExtension: "srt", type: UTType(filenameExtension: "srt") ?? .plainText) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(currentCues.isEmpty)
                        .help("Export SRT subtitles")
                    Button("WebVTT") { save(content: SubtitleFormatter.vtt(currentCues), fileExtension: "vtt", type: UTType(filenameExtension: "vtt") ?? .plainText) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(currentCues.isEmpty)
                        .help("Export WebVTT subtitles")
                    Button("Save text…", icon: .download) { save(content: currentText, fileExtension: "txt", type: .plainText) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, Theme.rowPaddingH)
                .padding(.vertical, Theme.s3)
            }
            .surface(.outlined)
        }
    }

    private var recentSessionsCard: some View {
        PageSection("Recent") {
                if !historySessions.isEmpty {
                    SearchField(prompt: "Search", text: $historySearch,
                                accessibilityLabel: "Search file transcripts")
                }
                if !historySessions.isEmpty || model.fileTranscriptionHistoryArchiveUnreadable {
                    Menu {
                        Button(!model.fileTranscriptionHistoryArchiveUnreadable ? "Delete all…" : "Remove unreadable archive…",
                               role: .destructive) { confirmClearHistory = true }
                    } label: {
                        Glyph(.more)
                    }
                    .menuStyle(.button)
                    .buttonStyle(IconButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
                }
        } content: {
            if let message = model.fileTranscriptionHistoryMessage {
                Label(message, icon: .warning)
                    .font(.hkCaption).foregroundStyle(Theme.finishing)
            }
            if filteredSessions.isEmpty {
                EmptyState(icon: historySearch.isEmpty ? .clock : .search,
                           title: historySearch.isEmpty ? "No file transcripts yet" : "No matches",
                           message: historySearch.isEmpty ? "Finished transcripts stay here, on this Mac."
                               : "Search by file name or words in the transcript.")
            } else {
                ListGroup {
                    ForEach(filteredSessions) { session in
                        ListRow {
                            Button { restore(session) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: Theme.s4) {
                                    VStack(alignment: .leading, spacing: Theme.s0) {
                                        Text(session.sourceName).font(.hkRowTitle).lineLimit(1)
                                        Text(session.text).font(.hkCallout).foregroundStyle(Theme.ink2).lineLimit(1)
                                    }
                                    Spacer(minLength: Theme.s2)
                                    Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.hkSubhead.monospacedDigit())
                                        .foregroundStyle(Theme.ink3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open this transcript")
                        } actions: {
                            Button("Delete \(session.sourceName)", icon: .trash) { delete(session) }
                                .buttonStyle(IconButtonStyle())
                                .help("Delete")
                        }
                    }
                }
            }
        }
    }

    private func startTranscription() {
        guard let selectedURL = workspace.selectedURL else { return }
        guard persistActiveSession() else { return }
        pendingSaveTask?.cancel()
        let sessionID = UUID()
        workspace.activeSessionID = sessionID
        workspace.activeSourceName = selectedURL.lastPathComponent
        switch workspace.engine {
        case .parakeet: workspace.activeLanguageIdentifier = "en"
        case .apple: workspace.activeLanguageIdentifier = model.dictationLanguage
        case .whisperKit: workspace.activeLanguageIdentifier = whisper.selectedLanguage
        }
        workspace.activeModelVariant = workspace.engine == .whisperKit ? whisper.selectedVariant.rawValue : nil
        let languageIdentifier = workspace.activeLanguageIdentifier
        exportMessage = nil

        if workspace.engine == .parakeet {
            parakeet.transcribe(file: selectedURL, engine: model.parakeet,
                                vocabulary: model.fileTranscriptionVocabulary, sessionID: sessionID)
        } else if workspace.engine == .apple {
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
        guard !isBusy, workspace.activeSessionID != nil else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistActiveSession()
        }
    }

    @discardableResult
    private func persistActiveSession(switchingTo targetSessionID: UUID? = nil) -> Bool {
        pendingSaveTask?.cancel()
        guard let session = FileTranscriptionSessionSnapshot.make(
            activeSessionID: workspace.activeSessionID, switchingTo: targetSessionID,
            sourceName: workspace.activeSourceName ?? workspace.selectedURL?.lastPathComponent ?? "Audio transcript",
            engine: workspace.engine, languageIdentifier: workspace.activeLanguageIdentifier,
            modelVariant: workspace.activeModelVariant, text: currentText, cues: currentCues) else { return true }
        return model.saveFileTranscriptionSession(session)
    }

    private func restore(_ session: FileTranscriptionSession) {
        guard !isBusy, workspace.activeSessionID != session.id else { return }
        guard persistActiveSession(switchingTo: session.id) else { return }
        workspace.engine = session.engine
        workspace.selectedURL = nil
        workspace.activeSessionID = session.id
        workspace.activeSourceName = session.sourceName
        workspace.activeLanguageIdentifier = session.languageIdentifier
        workspace.activeModelVariant = session.modelVariant
        exportMessage = "Restored. The audio file itself isn’t kept."
        if session.engine == .parakeet {
            parakeet.restore(session)
        } else if session.engine == .apple {
            transcription.restore(session)
        } else {
            whisper.restore(session)
        }
    }

    private func delete(_ session: FileTranscriptionSession) {
        if model.deleteFileTranscriptionSession(session), workspace.activeSessionID == session.id {
            workspace.activeSessionID = nil
        }
    }

    private func clearHistory() {
        if model.clearFileTranscriptionHistory() {
            workspace.activeSessionID = nil
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .quickTimeMovie, .mpeg4Movie]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose Recording"
        if panel.runModal() == .OK, let url = panel.url {
            selectFile(url)
        }
    }

    private func selectFile(_ url: URL) {
        guard url.isFileURL, !isBusy else { return }
        FileTranscriptionSourceSwitchGate.run(
            saveCurrentSession: { persistActiveSession() },
            switchSource: {
                pendingSaveTask?.cancel()
                workspace.selectedURL = url
                workspace.activeSessionID = nil
                workspace.activeSourceName = nil
                workspace.activeLanguageIdentifier = ""
                workspace.activeModelVariant = nil
                exportMessage = nil
                transcription.clear()
                whisper.clear()
                parakeet.clear()
            })
    }

    private func save(content: String, fileExtension: String, type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let sourceName = workspace.selectedURL?.lastPathComponent ?? workspace.activeSourceName ?? "Dictator-transcript"
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
