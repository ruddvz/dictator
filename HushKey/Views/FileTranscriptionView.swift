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
            VStack(alignment: .leading, spacing: Theme.s6) {
                PageHeader(eyebrow: "", title: "Files",
                           subtitle: "Turn a recording into text and subtitles, on this Mac.") {
                    Button("Choose file…", systemImage: "folder") { chooseFile() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isBusy)
                }

                sourceCard

                SettingsGroup(title: "Engine") {
                    SettingsRow(title: "Speech engine",
                                detail: engine == .apple ? "Apple Speech. Nothing to download."
                                    : "WhisperKit. Downloads a model once, then runs offline.") {
                        MenuPicker(selection: $engine,
                                   options: FileTranscriptionEngine.allCases.map { ($0, $0.rawValue) })
                            .disabled(isBusy || !currentText.isEmpty)
                    }
                    SettingsRow(title: "Language", detail: nil) {
                        if engine == .apple {
                            MenuPicker(selection: Binding(get: { model.dictationLanguage },
                                                          set: { model.dictationLanguage = $0 }),
                                       options: DictationLanguage.onDevice.map { ($0.identifier, $0.name) })
                                .disabled(isBusy)
                        } else {
                            MenuPicker(selection: $whisper.selectedLanguage,
                                       options: WhisperKitLanguage.options.map { ($0.identifier, $0.name) })
                                .disabled(isBusy)
                        }
                    }
                    if engine == .whisperKit {
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
            .pageLayout()
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
        .confirmationDialog(!model.fileTranscriptionHistoryArchiveUnreadable
                            ? "Delete all saved file transcripts?" : "Remove unreadable transcript archive?",
                            isPresented: $confirmClearHistory,
                            titleVisibility: .visible) {
            Button(!model.fileTranscriptionHistoryArchiveUnreadable ? "Delete transcripts" : "Remove archive",
                   role: .destructive) { clearHistory() }
        } message: {
            if let recoveryCopyURL = model.fileTranscriptionHistoryRecoveryCopyURL {
                Text("HushKey kept a recovery copy at \(recoveryCopyURL.path). Removing the unreadable file lets new transcripts save normally.")
            } else if model.fileTranscriptionHistoryArchiveUnreadable {
                Text("HushKey could not make a recovery copy. The original file remains in place until you remove it.")
            } else {
                Text("This removes HushKey’s saved transcript text and subtitle cues from this Mac. Original audio files are not stored here. Any transcription already running can still be exported, but will not be added back to history.")
            }
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { currentText }, set: { engine == .apple ? transcription.replaceText($0) : whisper.replaceText($0) })
    }

    /// The file and its one action, like Wispr's hero cards: big, calm, obvious.
    private var sourceCard: some View {
        @Bindable var whisper = model.whisperFileTranscriber
        let sourceName = selectedURL?.lastPathComponent ?? activeSourceName
        return HStack(spacing: Theme.s4) {
            Image(systemName: sourceName == nil ? "waveform.badge.plus" : "waveform")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.signal)
                .frame(width: 52, height: 52)
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceName ?? "Choose an audio or video file")
                    .font(.hkTitle3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Group {
                    if let error = currentError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    } else if let status = currentStatus {
                        Text(status).foregroundStyle(Theme.ink2)
                    } else {
                        Text("M4A, MP3, WAV, MOV and more. The audio itself is never kept.")
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .font(.hkCallout)
                .lineLimit(2)
            }
            Spacer(minLength: Theme.s4)
            if engine == .apple && transcription.isTranscribing {
                Button("Cancel") { transcription.cancel() }
                    .buttonStyle(SecondaryButtonStyle())
            } else if engine == .whisperKit && whisper.isTranscribing {
                Button("Cancel") { whisper.cancelTranscription() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(whisper.status == "Cancelling transcription…")
            }
            if selectedURL == nil && !isBusy {
                Button("Choose file…") { chooseFile() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(action: startTranscription) {
                    Label(isBusy ? "Working…" : "Transcribe", systemImage: isBusy ? "hourglass" : "waveform")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedURL == nil || isBusy ||
                          (engine == .whisperKit && !whisper.selectedModelIsDownloaded))
            }
        }
        .padding(Theme.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.signalSoft, in: RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Transcript").font(.hkTitle3)
                Spacer()
                Text("\(currentCues.count) timed segments")
                    .font(.hkMeta.monospacedDigit())
                    .foregroundStyle(Theme.ink3)
            }
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: transcriptBinding)
                    .font(.hkBody)
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .disabled(isBusy)
                    .padding(Theme.s3)
                RowDivider()
                HStack(spacing: Theme.s2) {
                    Text(exportMessage ?? "Edits save automatically. Subtitles keep the original timing.")
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                    Spacer()
                    Button("SRT") { save(content: SubtitleFormatter.srt(currentCues), fileExtension: "srt", type: UTType(filenameExtension: "srt") ?? .plainText) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(currentCues.isEmpty)
                        .help("Export SRT subtitles")
                    Button("WebVTT") { save(content: SubtitleFormatter.vtt(currentCues), fileExtension: "vtt", type: UTType(filenameExtension: "vtt") ?? .plainText) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(currentCues.isEmpty)
                        .help("Export WebVTT subtitles")
                    Button("Save text…", systemImage: "square.and.arrow.down") { save(content: currentText, fileExtension: "txt", type: .plainText) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, Theme.s4)
                .padding(.vertical, Theme.s3)
            }
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                Text("Recent").font(.hkTitle3)
                Spacer()
                if !historySessions.isEmpty {
                    HStack(spacing: Theme.s2) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.ink3)
                        TextField("Search", text: $historySearch)
                            .textFieldStyle(.plain)
                            .frame(width: 160)
                    }
                    .font(.hkCallout)
                    .padding(.horizontal, Theme.s3)
                    .frame(height: Theme.controlHeight - 4)
                    .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1))
                }
                if !historySessions.isEmpty || model.fileTranscriptionHistoryArchiveUnreadable {
                    Menu {
                        Button(!model.fileTranscriptionHistoryArchiveUnreadable ? "Delete all…" : "Remove unreadable archive…",
                               role: .destructive) { confirmClearHistory = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .buttonStyle(IconButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
                }
            }
            if let message = model.fileTranscriptionHistoryMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.hkCaption).foregroundStyle(Theme.finishing)
            }
            if filteredSessions.isEmpty {
                EmptyState(systemImage: historySearch.isEmpty ? "clock" : "magnifyingglass",
                           title: historySearch.isEmpty ? "No file transcripts yet" : "No matches",
                           message: historySearch.isEmpty ? "Finished transcripts stay here, on this Mac."
                               : "Search by file name or words in the transcript.")
                    .card(padding: 0, style: .outlined)
            } else {
                ListGroup {
                    ForEach(filteredSessions) { session in
                        ListRow {
                            Button { restore(session) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: Theme.s4) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(session.sourceName).font(.hkRowTitle).lineLimit(1)
                                        Text(session.text).font(.hkCallout).foregroundStyle(Theme.ink2).lineLimit(1)
                                    }
                                    Spacer(minLength: Theme.s2)
                                    Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 14).monospacedDigit())
                                        .foregroundStyle(Theme.ink3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open this transcript")
                        } actions: {
                            Button("Delete \(session.sourceName)", systemImage: "trash") { delete(session) }
                                .buttonStyle(IconButtonStyle())
                                .help("Delete")
                        }
                    }
                }
            }
        }
    }

    private func startTranscription() {
        guard let selectedURL else { return }
        guard persistActiveSession() else { return }
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

    @discardableResult
    private func persistActiveSession(switchingTo targetSessionID: UUID? = nil) -> Bool {
        pendingSaveTask?.cancel()
        guard let session = FileTranscriptionSessionSnapshot.make(
            activeSessionID: activeSessionID, switchingTo: targetSessionID,
            sourceName: activeSourceName ?? selectedURL?.lastPathComponent ?? "Audio transcript",
            engine: engine, languageIdentifier: activeLanguageIdentifier,
            modelVariant: activeModelVariant, text: currentText, cues: currentCues) else { return true }
        return model.saveFileTranscriptionSession(session)
    }

    private func restore(_ session: FileTranscriptionSession) {
        guard !isBusy, activeSessionID != session.id else { return }
        guard persistActiveSession(switchingTo: session.id) else { return }
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
        if model.deleteFileTranscriptionSession(session), activeSessionID == session.id {
            activeSessionID = nil
        }
    }

    private func clearHistory() {
        if model.clearFileTranscriptionHistory() {
            activeSessionID = nil
        }
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
