import AppKit
import UniformTypeIdentifiers

/// Meeting capture as the pill, the menu bar and the Meeting notes page share it: one start, one
/// stop, and the actions on the finished meeting card (Open, Copy, Export).
extension AppModel {
    /// Whether dictation or a voice edit holds the microphone, so a meeting can't start now.
    var dictationIsBusyForMeeting: Bool {
        audio.isRunning || audio.isStarting || isStartingDictation || isFinalizingDictation ||
            transcriber.isRunning || transcriber.isFinalizing
    }

    /// Starts a meeting from the remembered source (microphone, Mac audio or both), with your
    /// microphone, language and vocabulary. Capture is shown on the pill and in the toolbar.
    func startMeeting() {
        let meeting = meetingNotes
        guard !meeting.isStarting, !meeting.isCapturing, !meeting.isFinalizing else { return }
        meeting.transforms = localTransformService
        if meeting.audioSource != .systemAudio {
            meeting.audio.selectedDeviceID = audio.selectedDeviceID
        }
        let busy = dictationIsBusyForMeeting
        Task {
            await meeting.start(
                localeIdentifier: dictationLanguage,
                contextualStrings: DictationContextHints.prioritized(
                    customWords: DictationContextHints.builtInWords + DictationVocabulary.terms(from: dictationTerms),
                    learnedWords: dataset.vocabulary),
                dictationIsBusy: busy)
        }
    }

    /// The pill's meeting button: starts, cancels a start that hangs, or stops and saves.
    func toggleMeetingFromPill() {
        let meeting = meetingNotes
        if meeting.isCapturing || meeting.isStarting {
            meeting.stop()
        } else if !meeting.isFinalizing {
            startMeeting()
        }
    }

    /// Brings HushKey forward on one meeting note.
    func openMeetingNote(_ id: UUID) {
        meetingNotes.select(id)
        meetingNotes.dismissResult()
        openMeetingNotes()
    }

    /// Copies the whole note (summary, action items, transcript) as Markdown.
    @discardableResult
    func copyMeetingNote(_ id: UUID) -> Bool {
        guard let note = meetingNotes.notes.first(where: { $0.id == id }) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(MeetingDigest.markdown(for: note), forType: .string)
    }

    /// Saves the note as a Markdown file wherever you choose. HushKey comes forward first: the
    /// pill's panel never takes focus, so a save dialog on its own would open behind other apps.
    func exportMeetingNote(_ id: UUID) {
        guard let note = meetingNotes.notes.first(where: { $0.id == id }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "Export meeting notes"
        panel.nameFieldStringValue = MeetingDigest.filename(for: note.title)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(MeetingDigest.markdown(for: note).utf8).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            meetingNotes.setMessage("Export failed: \(error.localizedDescription)")
        }
    }
}
