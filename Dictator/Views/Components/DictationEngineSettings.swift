import DictatorParakeet
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
                HStack(spacing: Theme.s2) {
                    Text(parakeet.model.title)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                        .accessibilityLabel("Selected model: \(parakeet.model.title)")
                    // Before a download, the download is this row's own control, not a row of its own.
                    if needsDownload {
                        Button(downloadTitle) { parakeet.download() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .fixedSize()
            }
            if !needsDownload {
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

    /// Not downloaded and not mid-download or warm-up: the row offers the download itself.
    private var needsDownload: Bool {
        let parakeet = model.parakeet
        return !parakeet.isDownloaded && parakeet.phase != .downloading && parakeet.phase != .warmingUp
    }

    private var engineDetail: String {
        switch model.dictationEngine {
        case .appleSpeech:
            "Built into macOS. No download, and words appear as you speak."
        case .parakeet:
            "Parakeet Unified runs locally on this Mac. Dictation is English-only and the final text arrives when you let go."
        }
    }

    private var modelDetail: String {
        let parakeet = model.parakeet
        if !parakeet.model.supports(localeIdentifier: model.dictationLanguage) {
            let language = Locale.current.localizedString(forIdentifier: model.dictationLanguage) ?? model.dictationLanguage
            return "Parakeet Unified is configured for English. \(language) dictation uses Apple Speech."
        }
        return parakeet.statusDescription
    }

    private var needsAttention: Bool {
        if case .failed = model.parakeet.phase { return true }
        return !model.parakeet.model.supports(localeIdentifier: model.dictationLanguage)
    }

    private var downloadTitle: String {
        if case .failed = model.parakeet.phase { return "Try again" }
        return "Download"
    }
}
