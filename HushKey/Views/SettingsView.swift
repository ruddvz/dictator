import CoreAudio
import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "Manage",
                    title: "Settings & data",
                    subtitle: "Set up local dictation, safe text insertion, and the separate silent-mouthing experiment.")

                DictationSettingsCard()
                ShortcutSettingsCard()
                TextInsertionSettingsCard()
                MicrophoneCard()
                RecordingCard()
                ResearchReportsCard()
                DataManagementCard()
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct ResearchReportsCard: View {
    @State private var status: String?

    var body: some View {
        GroupBox("Research reports") {
            VStack(alignment: .leading, spacing: 8) {
                Text("The supplied comparison and HushKey's competitor notes are bundled with this app and open locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Wispr Flow vs TypeWhisper report", systemImage: "doc.text.magnifyingglass") {
                    openResource("Wispr_Flow_vs_TypeWhisper_Research_Report_2026-11-01", extension: "pdf")
                }
                Button("Open HushKey competitor notes", systemImage: "list.bullet.rectangle") {
                    openResource("COMPETITOR_RESEARCH", extension: "md")
                }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private func openResource(_ name: String, extension fileExtension: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            status = "This report is missing from the app bundle."
            return
        }
        status = NSWorkspace.shared.open(url) ? "Opened locally." : "macOS could not open this report."
    }
}

private struct DictationSettingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        GroupBox("Voice & whisper dictation") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("On-device speech language", selection: $model.dictationLanguage) {
                    ForEach(DictationLanguage.onDevice) { language in
                        Text(language.name).tag(language.identifier)
                    }
                    if !DictationLanguage.onDevice.contains(where: { $0.identifier == model.dictationLanguage }) {
                        Text(Locale.current.localizedString(forIdentifier: model.dictationLanguage) ?? model.dictationLanguage)
                            .tag(model.dictationLanguage)
                    }
                }
                .frame(maxWidth: 340, alignment: .leading)
                Text("Only languages supported for on-device recognition on this Mac appear here. No remote fallback is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Apply explicit spoken corrections", isOn: $model.appliesSpokenCorrections)
                Text("Recognizes cues such as “scratch that” or “actually” after a pause. The original recognition stays available to restore.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Use nearby text as optional vocabulary hints", isOn: $model.usesNearbyTextHints)
                Text("When started with the global shortcut in another app, HushKey can read a small slice around the cursor in a supported text field. It extracts terms locally for on-device recognition, then discards the slice. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Check local context access…") { model.requestNearbyTextAccess() }
                    Text(model.insertion.contextAccessStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Start or stop dictation", selection: $model.dictationShortcut) {
                    ForEach(DictationShortcut.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 280, alignment: .leading)
                Picker("Shortcut behavior", selection: $model.dictationCaptureBehavior) {
                    ForEach(DictationCaptureBehavior.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Text(model.dictationShortcutStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Personal vocabulary")
                    .font(.callout.weight(.medium))
                TextEditor(text: $model.dictationTerms)
                    .font(.body)
                    .frame(height: 72)
                    .padding(4)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                Text("Add names or special terms, separated by commas or new lines. HushKey passes these as local recognition hints; spelling is not guaranteed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Voice snippets")
                    .font(.callout.weight(.medium))
                TextEditor(text: $model.dictationSnippets)
                    .font(.body.monospaced())
                    .frame(height: 74)
                    .padding(4)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                Text("One per line: spoken cue => expanded phrase. HushKey expands complete cue matches locally when you stop dictating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Save recent transcripts on this Mac", isOn: $model.savesDictationHistory)
                Text("Turn this off to stop adding new dictations to history. Clear saved text from the Dictation screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct ShortcutSettingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        GroupBox("Capture shortcut") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Hold to capture", selection: $model.captureShortcut) {
                    ForEach(CaptureShortcut.allCases) { Text($0.label).tag($0) }
                }
                .frame(maxWidth: 260, alignment: .leading)
                Text("Use it in Train to capture a word, or in Use after the evidence gate passes. While a synchronized session is recording, it can also mark utterances from any HushKey screen. It does not intercept Space in other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct TextInsertionSettingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var insertion = model.insertion
        GroupBox("Optional Accessibility insertion") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(insertion.isEnabled ? "Disable insertion" : "Enable insertion") {
                        insertion.isEnabled ? insertion.disable() : insertion.enable()
                    }
                    .buttonStyle(.borderedProminent)
                    Picker("Shortcut", selection: $insertion.shortcut) {
                        ForEach(InsertionShortcut.allCases) { Text($0.label).tag($0) }
                    }
                    .frame(width: 170)
                    .disabled(!insertion.isEnabled)
                }
                Label(insertion.status, systemImage: insertion.isEnabled ? "checkmark.shield" : "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("If the destination field remains focused and unchanged, press ⌥⇧U immediately after insertion to undo it. Undo is fail-closed if the target or text changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("When enabled, the insertion shortcut adds your reviewed voice transcript, or the latest accepted silent word, to a supported text field in the frontmost app. Password fields are rejected. Explicit insertion does not use the clipboard. Silent Use still needs evidence to unlock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct MicrophoneCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var audio = model.audio
        GroupBox("Microphone input") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Input", selection: $audio.selectedDeviceID) {
                    Text("System default").tag(AudioDeviceID?.none)
                    ForEach(audio.devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                HStack {
                    Button("Refresh inputs", systemImage: "arrow.clockwise") { audio.refreshDevices() }
                    LevelMeter(value: Double(audio.level))
                }
                if let name = audio.activeDeviceName {
                    Label("Listening with \(name)", systemImage: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = audio.error ?? model.transcriber.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text("Choose an input here, then start dictation from the Dictation screen. Recognition stays on this Mac when on-device speech is available; dictation audio is not saved. The separate research recorder saves audio only when you explicitly start a session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct RecordingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var recorder = model.recorder
        GroupBox("Synchronized session recording") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Condition", selection: $recorder.condition) {
                    ForEach(SessionRecorder.Condition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(recorder.isRecording)

                TextField("Prompt or phrase label", text: $recorder.prompt)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        recorder.isRecording ? recorder.stop() : recorder.start(audio: model.audio)
                    } label: {
                        Label(recorder.isRecording ? "Stop recording" : "Start recording",
                              systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                    }
                    .tint(recorder.isRecording ? .red : .accentColor)
                    .buttonStyle(.borderedProminent)

                    if recorder.isRecording, let startedAt = recorder.startedAt {
                        Text(startedAt, style: .timer).monospacedDigit()
                        Text("· \(recorder.motionCount) samples · \(recorder.eventCount) marks")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = recorder.lastSessionURL {
                        Button("Show last session") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                }
                Text("This writes synchronized motion CSV and optional microphone audio to your local Sessions folder. It is separate from per-word templates. While recording, use \(model.captureShortcut.label) to mark an utterance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = recorder.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}

private struct DataManagementCard: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteTemplates = false
    @State private var confirmDeleteSessions = false

    var body: some View {
        GroupBox("Local files & privacy") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Templates stay in Application Support. Session CSV and optional audio stay in Documents. HushKey sends no recordings or templates anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Export dataset…", systemImage: "square.and.arrow.up") { model.exportDataset() }
                    Button("Export sessions…", systemImage: "folder.badge.plus") { model.exportSessions() }
                    Button("Delete templates…", systemImage: "trash", role: .destructive) {
                        confirmDeleteTemplates = true
                    }
                    Button("Delete session logs…", systemImage: "trash.slash", role: .destructive) {
                        confirmDeleteSessions = true
                    }
                    .disabled(model.recorder.isRecording)
                }
                if let message = model.dataMessage {
                    Text(message).font(.caption).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .confirmationDialog("Delete all training templates from this Mac?", isPresented: $confirmDeleteTemplates, titleVisibility: .visible) {
            Button("Delete templates", role: .destructive) { model.clearTrainingData() }
        }
        .confirmationDialog("Delete all session logs and local audio files?", isPresented: $confirmDeleteSessions, titleVisibility: .visible) {
            Button("Delete session logs", role: .destructive) { model.deleteSessionLogs() }
        }
    }
}
