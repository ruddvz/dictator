import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum FileTranscriptionEngine: String, CaseIterable, Identifiable {
    case apple = "Apple Speech"
    case whisperKit = "WhisperKit model"
    var id: String { rawValue }
}

struct FileTranscriptionView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedURL: URL?
    @State private var exportMessage: String?
    @State private var engine: FileTranscriptionEngine = .apple

    private var transcription: LocalFileTranscriber { model.fileTranscriber }
    private var whisper: WhisperKitFileTranscriber { model.whisperFileTranscriber }
    private var isBusy: Bool { transcription.isTranscribing || whisper.isTranscribing || whisper.isDownloading }
    private var currentText: String { engine == .apple ? transcription.text : whisper.text }
    private var currentCues: [SubtitleCue] { engine == .apple ? transcription.cues : whisper.cues }
    private var currentStatus: String? { engine == .apple ? transcription.status : whisper.status }
    private var currentError: String? { engine == .apple ? transcription.error : whisper.error }

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
                        .disabled(isBusy)

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
                            if let selectedURL {
                                Label(selectedURL.lastPathComponent, systemImage: "waveform")
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Button {
                                guard let selectedURL else { return }
                                if engine == .apple {
                                    Task {
                                        await transcription.transcribe(file: selectedURL,
                                                                       localeIdentifier: model.dictationLanguage)
                                    }
                                } else {
                                    whisper.transcribe(file: selectedURL,
                                                      languageIdentifier: whisper.selectedLanguage)
                                }
                            } label: {
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
                            Text("Subtitle files keep the original timed recognition segments. Edits in this text box are saved in the TXT export.")
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
            .pageLayout()
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { currentText }, set: { engine == .apple ? transcription.replaceText($0) : whisper.replaceText($0) })
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose Audio"
        if panel.runModal() == .OK, let url = panel.url {
            selectedURL = url
            exportMessage = nil
            transcription.clear()
            whisper.clear()
        }
    }

    private func save(content: String, fileExtension: String, type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = (selectedURL?.deletingPathExtension().lastPathComponent ?? "HushKey-transcript") + ".\(fileExtension)"
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
