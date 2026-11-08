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
    @State private var confirmRemoveUnreadableArchive = false
    @State private var confirmDiscardRecoveredDraft = false
    @State private var confirmRemoveUnreadableDraft = false
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
        PageColumn(maxWidth: Theme.homeWidth) {
            PageHeader(title: "Meeting notes",
                       subtitle: "Transcribe a meeting on this Mac, then draft a summary and action items.")

            captureControls

            if let draft = service.recoveredDraft {
                interruptedDraftCard(draft)
            }

            if let message = service.message {
                VStack(alignment: .leading, spacing: Theme.s2) {
                    Label(message, icon: .warning)
                        .font(.hkCallout)
                        .foregroundStyle(Theme.finishing)
                        .fixedSize(horizontal: false, vertical: true)
                    if service.archiveUnreadable {
                        Button("Remove unreadable archive…") { confirmRemoveUnreadableArchive = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    if service.draftArchiveUnreadable {
                        Button("Remove unreadable meeting draft…") { confirmRemoveUnreadableDraft = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }

            if hasNoNotesYet {
                // One empty state, not one per column.
                EmptyState(icon: .meetings, title: "Your notes stay here",
                           message: "Start a meeting and its transcript, summary and action items land here.")
                    .padding(.top, Theme.sectionGap)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: Theme.sectionGap) {
                    notesList
                        .frame(width: Theme.sideColumn)
                        .frame(maxHeight: .infinity, alignment: .top)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(minHeight: Theme.notesMinHeight, maxHeight: .infinity)
            }
        }
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
        .confirmationDialog("Remove unreadable meeting notes archive?",
                            isPresented: $confirmRemoveUnreadableArchive,
                            titleVisibility: .visible) {
            Button("Remove archive", role: .destructive) { service.removeUnreadableArchive() }
            Button("Cancel", role: .cancel) { confirmRemoveUnreadableArchive = false }
        } message: {
            if let recoveryCopyURL = service.recoveryCopyURL {
                Text("HushKey kept a recovery copy at \(recoveryCopyURL.path). Removing this unreadable file lets new meeting notes save normally.")
            } else {
                Text("HushKey could not make a recovery copy. The original file remains in place until you remove it.")
            }
        }
        .confirmationDialog("Discard this interrupted meeting transcript?",
                            isPresented: $confirmDiscardRecoveredDraft,
                            titleVisibility: .visible) {
            Button("Discard transcript", role: .destructive) { service.discardInterruptedMeetingDraft() }
            Button("Keep transcript", role: .cancel) { confirmDiscardRecoveredDraft = false }
        } message: {
            Text("This removes the locally recovered transcript from this Mac. Meeting audio was not saved.")
        }
        .confirmationDialog("Remove unreadable meeting draft?",
                            isPresented: $confirmRemoveUnreadableDraft,
                            titleVisibility: .visible) {
            Button("Remove draft", role: .destructive) { service.removeUnreadableDraftArchive() }
            Button("Cancel", role: .cancel) { confirmRemoveUnreadableDraft = false }
        } message: {
            if let recoveryCopyURL = service.draftRecoveryCopyURL {
                Text("HushKey kept a recovery copy at \(recoveryCopyURL.path). Removing this unreadable draft lets a new meeting start.")
            } else {
                Text("HushKey could not make a recovery copy. The original draft file remains until you remove it.")
            }
        }
        .onAppear {
            service.transforms = model.localTransformService
            if service.selectedNoteID == nil { service.select(service.notes.first?.id) }
        }
        .onChange(of: searchText) { _, _ in
            if selectedNote == nil {
                service.select(filteredNotes.first?.id)
            }
        }
    }

    /// The page's signature: a recorder-like control with a serif title, the source picker and
    /// a sage Start. While capturing, the live waveform and level meter take the title's place.
    private var captureControls: some View {
        @Bindable var meeting = service
        return HStack(spacing: Theme.s4) {
            VStack(alignment: .leading, spacing: Theme.s2) {
                if service.isCapturing {
                    HStack(spacing: Theme.s2) {
                        Glyph(.waveform)
                            .hushIconSize(Theme.iconL)
                            .foregroundStyle(Theme.listening)
                            .symbolEffect(.variableColor.iterative, isActive: service.isCapturing)
                        Text(captureStatusTitle).font(.hkTitle2)
                    }
                    HStack(spacing: Theme.s3) {
                        LevelMeter(value: Double(service.activeAudioLevel))
                            .frame(width: Theme.meterWidth)
                            .accessibilityLabel("Meeting audio input level")
                        Text(durationLabel(service.activeDuration))
                            .font(.hkCallout.monospacedDigit())
                            .foregroundStyle(Theme.ink2)
                    }
                } else if service.isFinalizing || service.isStarting {
                    Text(service.isFinalizing ? "Saving the transcript" : "Getting ready").font(.hkTitle2)
                    Text(service.isFinalizing ? "Finishing on this Mac…" : "Preparing local speech recognition…")
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                } else {
                    Text("Start a meeting").font(.hkTitle2)
                    Text(audioSourceDescription)
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.s4)
            if service.isCapturing {
                Button("Stop and save", icon: .stop) { service.stop(presentsResult: false) }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.ink))
            } else if service.isFinalizing {
                ProgressView().controlSize(.small)
            } else if service.isStarting {
                HStack(spacing: Theme.s2) {
                    ProgressView().controlSize(.small)
                    Button("Cancel", icon: .close) { service.cancelStarting() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                MenuPicker(selection: $meeting.audioSource,
                           options: MeetingAudioSource.allCases.map { ($0, $0.rawValue) },
                           width: Theme.menuWidth)
                Button("Start", icon: .record, action: startMeeting)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.captureGate.owner != nil || service.hasPendingDraftRecovery)
                    .help(service.hasPendingDraftRecovery
                          ? "Recover or discard the interrupted transcript before starting"
                          : "Start local meeting capture")
            }
        }
        .padding(Theme.cardPaddingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(service.isCapturing ? Theme.signalEdge : Theme.hairline, lineWidth: Theme.hairlineWidth))
        .animation(Theme.snappy, value: service.isCapturing)
    }

    private func interruptedDraftCard(_ draft: MeetingNotesDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.stackGap) {
            Label("Recovered unfinished meeting", icon: .undo)
                .font(.hkTitle3)
            Text("Partial transcript from \(draft.audioSource.rawValue.lowercased()), started \(draft.startedAt.formatted(date: .abbreviated, time: .shortened)), \(durationLabel(draft.duration)) long. Audio was not saved.")
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Text(draft.transcript)
                .font(.hkBody)
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Theme.s3)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.signalEdge).frame(width: Theme.ruleWidth)
                }
            HStack {
                Spacer()
                Button("Discard…", icon: .trash) { confirmDiscardRecoveredDraft = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Save recovered transcript", icon: .download) {
                    service.recoverInterruptedMeetingDraft()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card(padding: Theme.cardPaddingL, style: .soft)
    }

    private var hasNoNotesYet: Bool {
        filteredNotes.isEmpty && searchText.isEmpty && !service.isCapturing && !service.isFinalizing
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            SearchField(prompt: "Search notes", text: $searchText, width: nil,
                        accessibilityLabel: "Search meeting notes")

            if filteredNotes.isEmpty {
                EmptyState(icon: searchText.isEmpty ? .document : .search,
                           title: searchText.isEmpty ? "No notes yet" : "No matches",
                           message: searchText.isEmpty ? "Your meetings land here." : "Try another word.")
            } else {
                ScrollView {
                    VStack(spacing: Theme.s0) {
                        ForEach(filteredNotes) { note in
                            MeetingNoteRow(note: note, isSelected: service.selectedNoteID == note.id) {
                                service.select(note.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if service.isCapturing || service.isFinalizing {
            liveTranscript
        } else if let note = selectedNote {
            noteEditor(note)
        } else {
            EmptyState(icon: searchText.isEmpty ? .document : .search,
                       title: searchText.isEmpty ? "Your notes stay here" : "Pick a note",
                       message: searchText.isEmpty ? "Start a meeting. The transcript, summary and action items appear here."
                           : "Select a matching note, or clear the search.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleGap) {
            SectionTitle(service.isFinalizing ? "Saving transcript" : "Live transcript")
            ScrollView {
                Text(service.transcriber.text.isEmpty ? "Listening…" : service.transcriber.text)
                    .font(.hkBody)
                    .lineSpacing(Theme.leading)
                    .foregroundStyle(service.transcriber.text.isEmpty ? Theme.ink3 : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(Theme.cardPadding)
            }
            .frame(maxHeight: .infinity)
            .surface(.outlined)
            Text("Audio is never written to disk.")
                .font(.hkCaption)
                .foregroundStyle(Theme.ink3)
        }
    }

    private func noteEditor(_ note: MeetingNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                    VStack(alignment: .leading, spacing: Theme.s1) {
                        TextField("Meeting title", text: binding(for: note, keyPath: \.title))
                            .font(.hkTitle2)
                            .textFieldStyle(.plain)
                        HStack(spacing: Theme.s3) {
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Text(durationLabel(note.duration))
                            Text("On this Mac")
                        }
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                    }
                    Spacer(minLength: Theme.s1)
                    Menu {
                        Button("Export transcript…", systemImage: "doc.text") {
                            beginExport(note.transcript, title: note.title)
                        }
                        Button("Export as Markdown…", systemImage: "doc.richtext") {
                            model.exportMeetingNote(note.id)
                        }
                        Button("Copy as Markdown", systemImage: "doc.on.doc") {
                            model.copyMeetingNote(note.id)
                        }
                        Divider()
                        Button("Delete meeting note…", systemImage: "trash", role: .destructive) {
                            pendingDeleteID = note.id
                        }
                    } label: {
                        Glyph(.more)
                    }
                    .menuStyle(.button)
                    .buttonStyle(IconButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More meeting note actions")
                }

                if !model.localTransformService.modelIsAvailable {
                    Label(model.localTransformService.availabilityMessage, icon: .info)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                }

                noteSection("Summary", text: binding(for: note, keyPath: \.summary), minHeight: Theme.editorShort,
                            empty: "A few lines on what was decided.") {
                    Button("Draft", icon: .sparkle) {
                        Task { await service.generateSummary(for: note.id, with: model.localTransformService) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!canGenerate || model.localTransformService.isTransforming)
                }
                noteSection("Action items", text: binding(for: note, keyPath: \.actionItems), minHeight: Theme.editorShort,
                            empty: "Who does what, next.") {
                    Button("Extract", icon: .list) {
                        Task { await service.generateActionItems(for: note.id, with: model.localTransformService) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!canGenerate || model.localTransformService.isTransforming)
                }
                noteSection("Transcript", text: binding(for: note, keyPath: \.transcript), minHeight: Theme.editorTall,
                            empty: "") {
                    Text("\(note.transcript.count.formatted()) characters")
                        .font(.hkMeta.monospacedDigit())
                        .foregroundStyle(Theme.ink3)
                }
                if service.isGenerating {
                    ProgressView("Drafting on this Mac…").font(.hkCaption).controlSize(.small)
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    private func noteSection<Trailing: View>(_ title: String, text: Binding<String>, minHeight: CGFloat, empty: String,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(alignment: .leading, spacing: Theme.sectionTitleGap) {
            SectionTitle(title) { trailing() }
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty && !empty.isEmpty {
                    Text(empty)
                        .font(.hkBody)
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, Theme.s3 + Theme.textEditorInset)
                        .padding(.vertical, Theme.s3)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.hkBody)
                    .lineSpacing(Theme.leading)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .padding(Theme.s3)
                    .disabled(service.isGenerating)
            }
            .surface(.outlined)
        }
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
            "Your microphone. Voices in your headphones may be missed."
        case .systemAudio:
            "Sound from apps on this Mac, without your microphone."
        case .both:
            "Your microphone and Mac audio together."
        }
    }

    private var privacyNote: some View {
        Label("Transcribed on this Mac. Partial text is checkpointed for recovery; audio is never saved.",
              icon: .shield)
            .font(.hkCaption)
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func startMeeting() {
        model.startMeeting()
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

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// One note in the list: title, first line, and date, with a selection fill like the sidebar.
private struct MeetingNoteRow: View {
    var note: MeetingNote
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.s0) {
                Text(note.title).font(.hkRowTitle).lineLimit(1)
                Text(note.transcript.isEmpty ? "No transcript" : note.transcript)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.hkMeta)
                    .foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s3)
            .background(isSelected ? Theme.selection : hovering ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
