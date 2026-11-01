import Foundation
import Observation
import WhisperKit

struct WhisperKitLanguage: Identifiable, Hashable {
    let identifier: String
    let name: String
    var id: String { identifier }

    static let options = [
        WhisperKitLanguage(identifier: "", name: "Auto-detect"),
        WhisperKitLanguage(identifier: "en", name: "English"),
        WhisperKitLanguage(identifier: "ar", name: "Arabic"),
        WhisperKitLanguage(identifier: "zh", name: "Chinese"),
        WhisperKitLanguage(identifier: "nl", name: "Dutch"),
        WhisperKitLanguage(identifier: "fr", name: "French"),
        WhisperKitLanguage(identifier: "de", name: "German"),
        WhisperKitLanguage(identifier: "hi", name: "Hindi"),
        WhisperKitLanguage(identifier: "it", name: "Italian"),
        WhisperKitLanguage(identifier: "ja", name: "Japanese"),
        WhisperKitLanguage(identifier: "ko", name: "Korean"),
        WhisperKitLanguage(identifier: "pt", name: "Portuguese"),
        WhisperKitLanguage(identifier: "ru", name: "Russian"),
        WhisperKitLanguage(identifier: "es", name: "Spanish")
    ]
}

enum WhisperModelVariant: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case largeTurbo = "large-v3-v20240930_626MB"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .tiny: "Tiny · fastest, lower accuracy"
        case .base: "Base · balanced"
        case .small: "Small · larger, potentially more accurate"
        case .largeTurbo: "Large Turbo · about 626 MB"
        }
    }
}

@MainActor @Observable
final class WhisperKitFileTranscriber {
    private(set) var isDownloading = false
    private(set) var isTranscribing = false
    private(set) var downloadProgress: Double = 0
    private(set) var downloadCompletedBytes: Int64 = 0
    private(set) var downloadTotalBytes: Int64 = 0
    private(set) var text = ""
    private(set) var cues: [SubtitleCue] = []
    private(set) var status: String?
    private(set) var error: String?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    private(set) var downloadedModels: [String: String] = UserDefaults.standard.dictionary(forKey: "whisperKitModelPaths") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(downloadedModels, forKey: "whisperKitModelPaths") }
    }
    var selectedVariant = WhisperModelVariant(rawValue: UserDefaults.standard.string(forKey: "whisperKitModel") ?? "tiny") ?? .tiny {
        didSet { UserDefaults.standard.set(selectedVariant.rawValue, forKey: "whisperKitModel") }
    }
    var selectedLanguage = UserDefaults.standard.string(forKey: "whisperKitLanguage") ?? "" {
        didSet { UserDefaults.standard.set(selectedLanguage, forKey: "whisperKitLanguage") }
    }

    var downloadProgressDescription: String {
        let completed = ByteCountFormatter.string(fromByteCount: downloadCompletedBytes, countStyle: .file)
        if downloadTotalBytes > 0 {
            let total = ByteCountFormatter.string(fromByteCount: downloadTotalBytes, countStyle: .file)
            return "\(completed) of \(total) · \(Int(downloadProgress * 100))%"
        }
        return "\(completed) downloaded · \(Int(downloadProgress * 100))%"
    }

    var selectedModelIsDownloaded: Bool {
        guard let path = downloadedModels[selectedVariant.rawValue] else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private static var modelRoot: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "HushKey/WhisperKitModels", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func modelRoot(for variant: WhisperModelVariant) -> URL {
        let directory = modelRoot.appending(path: variant.rawValue, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func downloadSelectedModel() {
        guard !isDownloading, !selectedModelIsDownloaded else { return }
        isDownloading = true
        downloadProgress = 0
        downloadCompletedBytes = 0
        downloadTotalBytes = 0
        status = "Downloading \(selectedVariant.rawValue) from Hugging Face…"
        error = nil
        let variant = selectedVariant
        downloadTask = Task { [weak self] in await self?.performDownload(variant) }
    }

    func cancelDownload() {
        guard isDownloading else { return }
        status = "Cancelling model download…"
        downloadTask?.cancel()
    }

    private func performDownload(_ variant: WhisperModelVariant) async {
        do {
            let folder = try await WhisperKit.download(
                variant: variant.rawValue,
                downloadBase: Self.modelRoot(for: variant),
                useBackgroundSession: true,
                progressCallback: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress.fractionCompleted
                        self?.downloadCompletedBytes = progress.completedUnitCount
                        self?.downloadTotalBytes = max(0, progress.totalUnitCount)
                    }
                })
            try Task.checkCancellation()
            downloadedModels[variant.rawValue] = folder.path
            status = "\(variant.rawValue) is downloaded and stored on this Mac."
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: Self.modelRoot(for: variant))
            status = "Model download cancelled."
        } catch {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: Self.modelRoot(for: variant))
                status = "Model download cancelled."
            } else {
                self.error = "Model download failed: \(error.localizedDescription)"
                status = nil
            }
        }
        isDownloading = false
        downloadTask = nil
    }

    func removeSelectedModel() {
        guard !isDownloading, !isTranscribing, downloadedModels[selectedVariant.rawValue] != nil else { return }
        do {
            try FileManager.default.removeItem(at: Self.modelRoot(for: selectedVariant))
            downloadedModels[selectedVariant.rawValue] = nil
            status = "Removed \(selectedVariant.rawValue) from this Mac."
            error = nil
        } catch {
            self.error = "Model removal failed: \(error.localizedDescription)"
        }
    }

    func replaceText(_ value: String) {
        guard !isTranscribing else { return }
        text = value
    }

    func clear() {
        guard !isTranscribing else { return }
        text = ""
        cues = []
        status = nil
        error = nil
    }

    func transcribe(file url: URL, languageIdentifier: String) {
        guard !isTranscribing, !isDownloading else { return }
        guard selectedModelIsDownloaded,
              let modelPath = downloadedModels[selectedVariant.rawValue] else {
            error = "Download the selected model before using WhisperKit."
            return
        }
        isTranscribing = true
        status = "Loading the local model…"
        error = nil
        text = ""
        cues = []
        let variant = selectedVariant
        transcriptionTask = Task { [weak self] in
            await self?.performTranscription(file: url, modelPath: modelPath,
                                             variant: variant, languageIdentifier: languageIdentifier)
        }
    }

    func cancelTranscription() {
        guard isTranscribing else { return }
        status = "Cancelling transcription…"
        transcriptionTask?.cancel()
    }

    private func performTranscription(file url: URL, modelPath: String,
                                      variant: WhisperModelVariant, languageIdentifier: String) async {
        var whisper: WhisperKit?
        do {
            try Task.checkCancellation()
            let config = WhisperKitConfig(model: variant.rawValue, modelFolder: modelPath,
                                          verbose: false, logLevel: .error, download: false)
            whisper = try await WhisperKit(config)
            try Task.checkCancellation()
            status = "Transcribing locally…"
            let options = languageIdentifier.isEmpty
                ? DecodingOptions()
                : DecodingOptions(language: languageIdentifier)
            let results = try await whisper!.transcribe(
                audioPath: url.path,
                audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
                decodeOptions: options)
            try Task.checkCancellation()
            text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            cues = results.flatMap(\.segments).map {
                SubtitleCue(start: TimeInterval($0.start), duration: TimeInterval(max(0, $0.end - $0.start)), text: $0.text)
            }
            status = text.isEmpty ? "No speech was detected in this file." : "Finished locally. The source audio was not changed."
        } catch {
            if Task.isCancelled || error is CancellationError {
                status = "Transcription cancelled."
            } else {
                self.error = "WhisperKit transcription failed: \(error.localizedDescription)"
                status = nil
            }
        }
        await whisper?.unloadModels()
        isTranscribing = false
        transcriptionTask = nil
    }
}
