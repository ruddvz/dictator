import Foundation
import Observation

enum MeetingAudioSource: String, CaseIterable, Identifiable {
    case microphone = "Microphone"
    case systemAudio = "System audio"
    case both = "Both sides"

    var id: String { rawValue }

    var captureRoute: MeetingAudioCaptureRoute {
        self == .microphone ? .microphone : .systemAudio
    }
}

enum MeetingAudioCaptureRoute: Equatable {
    case microphone
    case systemAudio
}

/// Explicit meeting capture. Audio buffers are streamed to on-device Speech and never written to disk.
@MainActor @Observable
final class MeetingNotesService {
    let audio = AudioService()
    let systemAudio = SystemAudioService()
    let transcriber = MicTranscriber()

    private(set) var notes: [MeetingNote]
    private(set) var isStarting = false
    private(set) var isCapturing = false
    private(set) var isFinalizing = false
    private(set) var isGenerating = false
    private(set) var message: String?
    private(set) var recoveryCopyURL: URL?
    private(set) var archiveUnreadable = false
    private(set) var activeMeetingStartedAt: Date?
    private(set) var selectedNoteID: UUID?
    private(set) var activeAudioSource: MeetingAudioSource?
    var audioSource: MeetingAudioSource = MeetingAudioSource(
        rawValue: UserDefaults.standard.string(forKey: "meetingAudioSource") ?? "") ?? .microphone {
        didSet { UserDefaults.standard.set(audioSource.rawValue, forKey: "meetingAudioSource") }
    }

    @ObservationIgnored private let captureGate: AudioCaptureGate
    @ObservationIgnored private let notesURL: URL
    @ObservationIgnored private var generation = 0

    init(captureGate: AudioCaptureGate, notesURL: URL = MeetingNotesStore.url) {
        self.captureGate = captureGate
        self.notesURL = notesURL
        switch MeetingNotesStore.loadState(from: notesURL) {
        case .missing:
            self.notes = []
        case .loaded(let notes):
            self.notes = notes
        case .unreadable(let recoveryCopyURL):
            self.notes = []
            self.recoveryCopyURL = recoveryCopyURL
            self.archiveUnreadable = true
            self.message = Self.archiveRecoveryMessage(copy: recoveryCopyURL)
        }
    }

    var activeDuration: TimeInterval {
        guard let activeMeetingStartedAt else { return 0 }
        return Date().timeIntervalSince(activeMeetingStartedAt)
    }

    var activeAudioLevel: Float {
        activeAudioSource?.captureRoute == .microphone ? audio.level : systemAudio.level
    }

    func start(localeIdentifier: String, contextualStrings: [String] = [], dictationIsBusy: Bool) async {
        guard !isStarting, !isCapturing, !isFinalizing else { return }
        guard !dictationIsBusy, captureGate.claim(.meeting) else {
            message = "Finish the current dictation before starting meeting notes."
            return
        }

        isStarting = true
        message = nil
        generation += 1
        let startGeneration = generation
        transcriber.clear()

        let source = audioSource
        let sink = source == .microphone ? audio.sink : systemAudio.sink
        let speechReady = await transcriber.start(sink: sink, localeIdentifier: localeIdentifier,
                                                 contextualStrings: Array(contextualStrings.prefix(DictationContextHints.maximumCount)))
        guard startGeneration == generation else {
            transcriber.stop()
            captureGate.release(.meeting)
            isStarting = false
            return
        }
        guard speechReady else {
            message = transcriber.error ?? "On-device speech recognition is unavailable."
            captureGate.release(.meeting)
            isStarting = false
            return
        }

        switch source.captureRoute {
        case .microphone:
            await audio.start()
        case .systemAudio:
            await systemAudio.start(includeMicrophone: source == .both,
                                    microphoneDeviceID: source == .both ? audio.selectedDeviceID : nil)
        }
        let sourceStarted = source.captureRoute == .microphone ? audio.isRunning : systemAudio.isRunning
        guard startGeneration == generation, sourceStarted else {
            transcriber.stop()
            switch source.captureRoute {
            case .microphone:
                message = audio.error ?? "Microphone capture could not start."
            case .systemAudio:
                message = systemAudio.error ?? "Meeting audio capture could not start."
            }
            captureGate.release(.meeting)
            isStarting = false
            return
        }

        activeAudioSource = source
        activeMeetingStartedAt = Date()
        isCapturing = true
        isStarting = false
    }

    func stop() {
        guard isCapturing else { return }
        generation += 1
        isCapturing = false
        isFinalizing = true
        let stoppedAt = Date()
        transcriber.beginFinalization()
        switch activeAudioSource?.captureRoute {
        case .microphone:
            audio.stop()
        case .systemAudio:
            systemAudio.stop()
        case nil:
            break
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let transcript = await transcriber.waitForFinalization()
            let startedAt = activeMeetingStartedAt ?? stoppedAt
            activeMeetingStartedAt = nil
            activeAudioSource = nil
            transcriber.clear()

            let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTranscript.isEmpty {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                let note = MeetingNote(
                    createdAt: startedAt,
                    duration: max(0, stoppedAt.timeIntervalSince(startedAt)),
                    title: "Meeting · \(formatter.string(from: startedAt))",
                    transcript: cleanTranscript
                )
                notes.insert(note, at: 0)
                selectedNoteID = note.id
                persist()
            } else {
                message = "No speech was recognized, so no meeting note was saved."
            }

            isFinalizing = false
            captureGate.release(.meeting)
        }
    }

    func updateNote(_ note: MeetingNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index] = note
        persist()
    }

    func select(_ id: UUID?) {
        selectedNoteID = id
    }

    func setMessage(_ value: String) {
        message = value
    }

    func deleteNote(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        let updatedNotes = notes.filter { $0.id != id }
        let updatedSelection = selectedNoteID == id ? updatedNotes.first?.id : selectedNoteID
        do {
            try MeetingNotesStore.save(updatedNotes, to: notesURL)
            notes = updatedNotes
            selectedNoteID = updatedSelection
            message = nil
        } catch {
            message = "Meeting note could not be deleted: \(error.localizedDescription)"
        }
    }

    func removeUnreadableArchive() {
        guard archiveUnreadable else { return }
        let copy = recoveryCopyURL
        do {
            try MeetingNotesStore.delete(at: notesURL)
            notes = []
            selectedNoteID = nil
            recoveryCopyURL = nil
            archiveUnreadable = false
            message = copy.map { "Unreadable meeting notes were removed. Recovery copy: \($0.path)" }
                ?? "Unreadable meeting notes were removed. No recovery copy could be created."
        } catch {
            message = "Unreadable meeting notes could not be removed: \(error.localizedDescription)"
        }
    }

    func generateSummary(for id: UUID, with transforms: LocalTransformService) async {
        await generate(for: id, with: transforms, isActionItems: false)
    }

    func generateActionItems(for id: UUID, with transforms: LocalTransformService) async {
        await generate(for: id, with: transforms, isActionItems: true)
    }

    private func generate(for id: UUID, with transforms: LocalTransformService, isActionItems: Bool) async {
        guard !isCapturing, !isFinalizing, !isGenerating,
              let original = notes.first(where: { $0.id == id }),
              !original.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGenerating = true
        message = nil
        defer { isGenerating = false }

        do {
            let result = isActionItems
                ? try await transforms.extractMeetingActionItems(original.transcript)
                : try await transforms.summarizeMeeting(original.transcript)
            guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].transcript == original.transcript else {
                message = "The transcript changed while the local draft was being created. Run it again to use the latest text."
                return
            }
            if isActionItems { notes[index].actionItems = result }
            else { notes[index].summary = result }
            persist()
        } catch {
            message = error.localizedDescription
        }
    }

    private func persist() {
        do {
            try MeetingNotesStore.save(notes, to: notesURL)
            message = nil
        } catch {
            message = "Meeting note could not be saved: \(error.localizedDescription)"
        }
    }

    private static func archiveRecoveryMessage(copy: URL?) -> String {
        if let copy {
            return "Saved meeting notes could not be read. HushKey kept a recovery copy at \(copy.path). Remove the unreadable archive to continue saving notes."
        }
        return "Saved meeting notes could not be read. HushKey left the original file in place but could not make a recovery copy. Remove the unreadable archive to continue saving notes."
    }
}
