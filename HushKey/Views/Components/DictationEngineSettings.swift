import HushKeyParakeet
import SwiftUI

/// Settings rows for choosing the dictation engine and setting up Parakeet: size, download
/// progress, warm-up, language and the last dictation's timing.
struct DictationEngineRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var parakeet = model.parakeet

        SettingsRow(title: "Speech engine", detail: engineDetail) {
            MenuPicker(selection: $model.dictationEngine,
                       options: DictationEngine.allCases.map { ($0, $0.title) })
        }
        if model.dictationEngine == .parakeet {
            SettingsRow(title: "Parakeet model", detail: modelDetail,
                        detailTint: needsAttention ? Theme.danger : Theme.ink2) {
                MenuPicker(selection: $parakeet.model,
                           options: ParakeetModel.allCases.map { ($0, $0.title) })
                    .disabled(parakeet.isBusy || model.audio.isRunning || model.isFinalizingDictation)
            }
            GroupRow {
                if parakeet.phase == .downloading {
                    HStack(spacing: Theme.s3) {
                        ProgressView(value: parakeet.downloadFraction)
                            .tint(Theme.signal)
                            .accessibilityLabel("Downloading the Parakeet model")
                        Button("Cancel") { parakeet.cancelDownload() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                } else if parakeet.phase == .warmingUp {
                    HStack(spacing: Theme.s3) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Warming up Parakeet")
                        Text("First load compiles for the Neural Engine and can take a minute.")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }
                } else {
                    HStack(spacing: Theme.s2) {
                        if !parakeet.isDownloaded {
                            Button(downloadTitle) { parakeet.download() }
                                .buttonStyle(PrimaryButtonStyle())
                        } else {
                            if parakeet.isTranscribing {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("Transcribing with Parakeet")
                            }
                            if parakeet.phase != .ready {
                                Button("Load now") { parakeet.warmUp() }
                                    .buttonStyle(PrimaryButtonStyle())
                            }
                            Button("Remove model") { parakeet.removeModel() }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(parakeet.isBusy || model.audio.isRunning || model.isFinalizingDictation)
                        }
                    }
                }
            }
        }
    }

    private var engineDetail: String {
        switch model.dictationEngine {
        case .appleSpeech:
            "Built into macOS. No download, and words appear as you speak."
        case .parakeet:
            "NVIDIA's model on this Mac's Neural Engine. Text appears when you let go."
        }
    }

    private var modelDetail: String {
        let parakeet = model.parakeet
        if !parakeet.model.supports(localeIdentifier: model.dictationLanguage) {
            let language = Locale.current.localizedString(forIdentifier: model.dictationLanguage) ?? model.dictationLanguage
            return "The \(parakeet.model.title) model doesn't know \(language), so dictation uses Apple Speech. "
                + "Choose the 25-language model."
        }
        return parakeet.statusDescription
    }

    private var needsAttention: Bool {
        if case .failed = model.parakeet.phase { return true }
        return !model.parakeet.model.supports(localeIdentifier: model.dictationLanguage)
    }

    private var downloadTitle: String {
        if case .failed = model.parakeet.phase { return "Try again" }
        return "Download model"
    }
}
