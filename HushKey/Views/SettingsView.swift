import CoreAudio
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "Manage",
                    title: "Settings & data",
                    subtitle: "Optional recording, shortcuts, insertion, and local files stay separate from the core motion experiment.")

                ShortcutSettingsCard()
                TextInsertionSettingsCard()
                MicrophoneCard()
                RecordingCard()
                DataManagementCard()
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
                Text("When enabled, the shortcut inserts only the latest accepted word into a supported text field in the frontmost app. Password fields are rejected; the clipboard is not used. Use is disabled until the study passes its evidence checks.")
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
        GroupBox("Optional on-device speech reference") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Input", selection: $audio.selectedDeviceID) {
                    Text("System default").tag(AudioDeviceID?.none)
                    ForEach(audio.devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                HStack {
                    Button(audio.isRunning ? "Stop microphone" : "Start microphone") {
                        Task { await model.toggleMic() }
                    }
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
                Text("Recognition uses macOS on-device speech only. Audio is not saved unless a session recording is active. Choosing AirPods as the microphone may reduce playback quality.")
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
