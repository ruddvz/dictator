import AppKit
import SwiftUI

struct ResearchRecordingSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage("researchRecordingIncludesMicrophoneAudio") private var includesMicrophoneAudio = false

    var body: some View {
        @Bindable var recorder = model.recorder

        SettingsGroup(
            title: "Research capture",
            footer: recorder.error ?? "Saves motion locally. Microphone audio is optional and off by default. Hold \(model.captureShortcut.label) to mark an utterance."
        ) {
            SettingsRow(title: "Condition", detail: "Label for the next session.") {
                MenuPicker(selection: $recorder.condition,
                           options: SessionRecorder.Condition.allCases.map { ($0, $0.rawValue) })
            }
            .disabled(recorder.isRecording)

            SettingsRow(title: "Phrase label") {
                TextField("Optional", text: $recorder.prompt)
                    .textFieldStyle(.plain)
                    .font(.hkBody)
                    .padding(.horizontal, Theme.s3)
                    .frame(width: Theme.menuWidth, height: Theme.controlHeight)
                    .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
            }
            .disabled(recorder.isRecording)

            SettingsRow(title: "Microphone audio",
                        detail: microphoneAudioDetail) {
                RowToggle(isOn: $includesMicrophoneAudio, label: "Include audio")
            }
            .disabled(recorder.isRecording)

            SettingsRow(title: "Session", detail: recordingDetail) {
                HStack(spacing: Theme.s2) {
                    if !recorder.isRecording, let url = recorder.lastSessionURL {
                        Button("Show last") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button {
                        recorder.isRecording
                            ? recorder.stop()
                            : recorder.start(audio: model.audio, includeMicrophoneAudio: includesMicrophoneAudio)
                    } label: {
                        Label(recorder.isRecording ? "Stop" : "Start",
                              icon: recorder.isRecording ? .stop : .record)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: recorder.isRecording ? Theme.danger : Theme.signal))
                    .disabled(!recorder.isRecording && model.motion.status != .streaming)
                }
            }
        }
    }

    private var recordingDetail: String {
        let recorder = model.recorder
        if recorder.isRecording {
            return "\(recorder.motionCount) samples, \(recorder.eventCount) marks"
        }
        guard model.motion.status == .streaming else {
            return "Connect motion headphones before starting a capture."
        }
        return "Ready to record a local session."
    }

    private var microphoneAudioDetail: String {
        guard includesMicrophoneAudio else { return "Off by default. No microphone audio is saved." }
        guard model.audio.isRunning else { return "On, but no mic is active. This session will contain motion only." }
        return "On. The active Dictator mic stream is saved locally."
    }
}
