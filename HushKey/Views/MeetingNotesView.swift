import SwiftUI
import UniformTypeIdentifiers

private struct MeetingNoteDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct MeetingNotesView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var pendingDeleteID: UUID?
    @State private var exportDocument: MeetingNoteDocument?
    @State private var exportFilename = "HushKey Meeting Notes"
    @State private var isExporting = false

    private var service: MeetingNotesService { model.meetingNotes }
    private var selectedNote: MeetingNote? {
        guard let note = service.notes.first(where: { $0.id == service.selectedNoteID }),
              filteredNotes.contains(where: { $0.id == note.id }) else { return nil }
        return note
    }
    private var filteredNotes: [MeetingNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return service.notes }
        return service.notes.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.transcript.localizedCaseInsensitiveContains(query) ||
            $0.summary.localizedCaseInsensitiveContains(query) ||
            $0.actionItems.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                eyebrow: "LOCAL MEETING WORKSPACE",
                title: "Meeting notes",
                subtitle: "Capture a meeting transcript on this Mac, then create a reviewable summary and action list with Apple’s on-device model.")

            captureControls

            if let message = service.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HSplitView {
                notesList
                    .frame(minWidth: 220, idealWidth: 270, maxWidth: 340, maxHeight: .infinity)
                detail
                    .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 390, maxHeight: .infinity)

            privacyNote
        }
        .padding(24)
        .fileExporter(isPresented: $isExporting, document: exportDocument,
                      contentType: .plainText, defaultFilename: exportFilename) { result in
            if case .failure(let error) = result {
                service.setMessage("Export failed: \(error.localizedDescription)")
            }
            exportDocument = nil
        }
        .confirmationDialog("Delete this meeting note?", isPresented: Binding(
            get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } }),
            titleVisibility: .visible) {
            Button("Delete meeting note", role: .destructive) {
                if let pendingDeleteID { service.deleteNote(pendingDeleteID) }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("This removes the transcript and generated notes from HushKey on this Mac.")
        }
        .onAppear {
            if service.selectedNoteID == nil { service.select(service.notes.first?.id) }
        }
        .onChange(of: searchText) { _, _ in
            if selectedNote == nil {
                service.select(filteredNotes.first?.id)
            }
        }
    }

    private var captureControls: some View {
        @Bindable var meeting = service
        return GroupBox {
            HStack(spacing: 14) {
                if service.isCapturing {
                    Label(captureStatusTitle,
                          systemImage: "waveform.circle.fill")
                        .foregroundStyle(.red)
                    ProgressView(value: Double(service.activeAudioLevel))
                        .frame(maxWidth: 120)
                        .accessibilityLabel("Meeting audio input level")
                    Text(durationLabel(service.activeDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop and save", systemImage: "stop.fill") { service.stop() }
                        .buttonStyle(.borderedProminent)
                } else if service.isFinalizing {
                    ProgressView()
                    Text("Finishing the on-device transcript…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Finishing…") {}.disabled(true)
                } else if service.isStarting {
                    ProgressView()
                    Text("Preparing local speech recognition…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Starting…") {}.disabled(true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Meeting audio source", selection: $meeting.audioSource) {
                            ForEach(MeetingAudioSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)

                        Text(audioSourceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Start meeting", systemImage: service.audioSource == .microphone ? "record.circle" : "waveform",
                           action: startMeeting)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.captureGate.owner != nil)
                }
            }
            .padding(6)
        } label: {
            Label("Capture", systemImage: "mic.badge.plus")
        }
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search meeting notes", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search meeting notes")

            List(selection: Binding(get: { service.selectedNoteID }, set: { service.select($0) })) {
                if filteredNotes.isEmpty {
                    ContentUnavailableView(searchText.isEmpty ? "No meeting notes yet" : "No matches",
                                           systemImage: "text.badge.plus",
                                           description: Text(searchText.isEmpty
                                               ? "Start a meeting capture to save a local transcript."
                                               : "Try a different title or transcript phrase."))
                }
                ForEach(filteredNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title).font(.headline).lineLimit(1)
                        Text(note.transcript.isEmpty ? "No transcript" : note.transcript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .tag(note.id)
                }
            }
            .listStyle(.sidebar)
        }
        .padding(.trailing, 8)
    }

    @ViewBuilder
    private var detail: some View {
        if service.isCapturing || service.isFinalizing {
            liveTranscript
        } else if let note = selectedNote {
            noteEditor(note)
        } else {
            ContentUnavailableView(searchText.isEmpty ? "Your notes stay here" : "No meeting note selected",
                                   systemImage: searchText.isEmpty ? "waveform.and.text" : "text.magnifyingglass",
                                   description: Text(searchText.isEmpty
                                       ? "Start a meeting capture. HushKey transcribes on this Mac and does not keep microphone audio."
                                       : "Select a matching note or clear the search."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(service.isFinalizing ? "Saving meeting transcript" : "Live transcript",
                  systemImage: service.isFinalizing ? "ellipsis.circle" : "waveform")
                .font(.headline)
            TextEditor(text: .constant(service.transcriber.text))
                .font(.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .disabled(true)
            Text("Live text is temporary until you stop the capture. No microphone audio is written to disk.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private func noteEditor(_ note: MeetingNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("Meeting title", text: binding(for: note, keyPath: \.title))
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                Spacer(minLength: 4)
                Menu {
                    Button("Export transcript…", systemImage: "doc.text") {
                        beginExport(note.transcript, title: note.title)
                    }
                    Button("Export all notes…", systemImage: "doc.richtext") {
                        beginExport(exportText(for: note), title: note.title)
                    }
                    Divider()
                    Button("Delete meeting note…", systemImage: "trash", role: .destructive) {
                        pendingDeleteID = note.id
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .help("More meeting note actions")
            }
            Text("\(note.createdAt.formatted(date: .complete, time: .shortened)) · \(durationLabel(note.duration)) · Stored on this Mac")
                .font(.caption)
                .foregroundStyle(.secondary)

            if service.isGenerating {
                ProgressView("Creating a local draft…")
                    .font(.caption)
                    .padding(.vertical, 2)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Summary", systemImage: "text.alignleft")
                            .font(.headline)
                        Spacer()
                        Button("Create summary", systemImage: "sparkles") {
                            Task { await service.generateSummary(for: note.id, with: model.localTransformService) }
                        }
                        .disabled(!canGenerate || model.localTransformService.isTransforming)
                    }
                    TextEditor(text: binding(for: note, keyPath: \.summary))
                        .frame(minHeight: 86)
                        .disabled(service.isGenerating)
                    Text(model.localTransformService.availabilityMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Action items", systemImage: "checklist")
                            .font(.headline)
                        Spacer()
                        Button("Extract action items", systemImage: "list.bullet.clipboard") {
                            Task { await service.generateActionItems(for: note.id, with: model.localTransformService) }
                        }
                        .disabled(!canGenerate || model.localTransformService.isTransforming)
                    }
                    TextEditor(text: binding(for: note, keyPath: \.actionItems))
                        .frame(minHeight: 66)
                        .disabled(service.isGenerating)
                }
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Transcript", systemImage: "waveform")
                        .font(.headline)
                    TextEditor(text: binding(for: note, keyPath: \.transcript))
                        .font(.body)
                        .frame(minHeight: 160)
                        .disabled(service.isGenerating)
                    Text("\(note.transcript.count.formatted()) characters · Edit to correct recognition before generating notes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }
        }
        .padding(10)
    }

    private var canGenerate: Bool {
        selectedNote != nil && !service.isCapturing && !service.isFinalizing && !service.isGenerating &&
            model.localTransformService.modelIsAvailable
    }

    private var captureStatusTitle: String {
        switch service.activeAudioSource {
        case .microphone: "Capturing microphone"
        case .systemAudio: "Capturing system audio"
        case .both: "Capturing both sides"
        case nil: "Capturing meeting audio"
        }
    }

    private var audioSourceDescription: String {
        switch service.audioSource {
        case .microphone:
            "Captures your selected microphone. Remote voices routed to headphones may be missed."
        case .systemAudio:
            "Captures audio playing from apps on this Mac. Your microphone is not included."
        case .both:
            "Captures your selected microphone and Mac audio together. Requires both permissions."
        }
    }

    private var privacyNote: some View {
        Label("Start capture explicitly. Both sides combines your microphone with sound playing from apps. macOS may ask separately for microphone and System Audio Recording access. Speech recognition and notes stay on this Mac; audio is not saved and speakers are not identified.",
              systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func startMeeting() {
        if service.audioSource == .microphone || service.audioSource == .both {
            service.audio.selectedDeviceID = model.audio.selectedDeviceID
        }
        Task {
            await service.start(
                localeIdentifier: model.dictationLanguage,
                contextualStrings: DictationContextHints.prioritized(
                    customWords: DictationVocabulary.terms(from: model.dictationTerms),
                    learnedWords: model.dataset.vocabulary),
                dictationIsBusy: model.audio.isRunning || model.isFinalizingDictation ||
                    model.transcriber.isRunning || model.transcriber.isFinalizing)
        }
    }

    private func binding<Value>(for note: MeetingNote, keyPath: WritableKeyPath<MeetingNote, Value>) -> Binding<Value> {
        Binding(
            get: { service.notes.first(where: { $0.id == note.id })?[keyPath: keyPath] ?? note[keyPath: keyPath] },
            set: { value in
                guard var updated = service.notes.first(where: { $0.id == note.id }) else { return }
                updated[keyPath: keyPath] = value
                service.updateNote(updated)
            })
    }

    private func beginExport(_ text: String, title: String) {
        exportFilename = title.replacingOccurrences(of: "/", with: "-")
        exportDocument = MeetingNoteDocument(text: text)
        isExporting = true
    }

    private func exportText(for note: MeetingNote) -> String {
        var sections = [note.title, note.createdAt.formatted(date: .complete, time: .shortened), ""]
        if !note.summary.isEmpty { sections += ["SUMMARY", note.summary, ""] }
        if !note.actionItems.isEmpty { sections += ["ACTION ITEMS", note.actionItems, ""] }
        sections += ["TRANSCRIPT", note.transcript]
        return sections.joined(separator: "\n")
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
