import AVFoundation
import Foundation
import DictatorParakeet
import Observation

/// Which recognizer turns a dictation into text.
enum DictationEngine: String, CaseIterable, Identifiable {
    /// Apple's on-device Speech. Built in, nothing to download, shows words as you speak.
    case appleSpeech
    /// NVIDIA Parakeet TDT 0.6B on the Neural Engine. One-time model download; runs when fn is released.
    case parakeet

    static let storageKey = "dictationEngine"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .parakeet: "Parakeet"
        }
    }
}

extension ParakeetModel {
    var title: String { "English · Parakeet Unified" }

    /// Approximate download size; the real size is shown once it's on disk.
    var approximateBytes: Int64 { 610_000_000 }

    /// Language codes the model recognizes (two-letter, from the dictation locale).
    var languageCodes: Set<String> { ["en"] }

    func supports(localeIdentifier: String) -> Bool {
        let code = Locale(identifier: localeIdentifier).language.languageCode?.identifier
            ?? String(localeIdentifier.prefix(2))
        return languageCodes.contains(code.lowercased())
    }

    /// Dictator exposes one Parakeet model. Non-English locales fall back to Apple Speech.
    static func preferred(for localeIdentifier: String) -> ParakeetModel { .englishUnified }
}

/// Setup and recognition state for Parakeet dictation, shown in Settings and used by `AppModel`.
@MainActor @Observable
final class ParakeetDictationEngine {
    enum Phase: Equatable {
        case notDownloaded
        case downloading
        /// On disk, loads at the next dictation (or now, from Settings).
        case downloaded
        /// Loading the model into memory and running it once, so the first dictation is fast.
        case warmingUp
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .notDownloaded
    private(set) var activeTranscriptions = 0
    private(set) var downloadFraction: Double = 0
    private(set) var downloadDetail: String?
    private(set) var bytesOnDisk: Int64?
    /// The last dictation: audio length and how long Parakeet took, for the setup diagnostics.
    private(set) var lastRun: (audioSeconds: Double, processingSeconds: Double)?

    let model: ParakeetModel

    @ObservationIgnored private let recognizer = ParakeetRecognizer()
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var warmUpTask: Task<Bool, Never>?
    @ObservationIgnored private var warmUpModel: ParakeetModel?
    @ObservationIgnored private var loadedModel: ParakeetModel?
    @ObservationIgnored let modelRoot: URL

    static let modelKey = "parakeetModel"
    nonisolated static var defaultModelRoot: URL { AppDataDirectory.url.appending(path: "ParakeetModels", directoryHint: .isDirectory) }
    private let defaults: UserDefaults
    private var boostingTask: Task<Void, Never>?
    /// True once the word-spotting model is loaded, so the user's vocabulary steers recognition.
    private(set) var isVocabularyBoostingReady = false
    private static let removedByUserKey = "parakeetModelRemovedByUser"

    private static let legacyModelFolders = [
        "parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v3", "parakeet-ultra",
    ]

    init(modelRoot: URL = ParakeetDictationEngine.defaultModelRoot,
         model: ParakeetModel? = nil, defaults: UserDefaults = .standard) {
        self.modelRoot = modelRoot
        self.defaults = defaults
        self.model = model ?? .englishUnified
        // Rewrite any previous v2, v3, or Ultra choice to the single model now offered.
        defaults.set(self.model.rawValue, forKey: Self.modelKey)
        if modelRoot.standardizedFileURL == Self.defaultModelRoot.standardizedFileURL {
            let root = modelRoot
            Task.detached(priority: .utility) {
                Self.removeLegacyModelCaches(in: root)
            }
        }
        refresh()
    }

    /// Remove only the former model directories owned by Dictator. Other cache entries and
    /// shared FluidAudio caches are intentionally left untouched.
    nonisolated static func removeLegacyModelCaches(in root: URL) {
        let fileManager = FileManager.default
        for folder in legacyModelFolders {
            let directory = root.appending(path: folder, directoryHint: .isDirectory)
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    var isDownloaded: Bool { model.isDownloaded(in: modelRoot) }
    var isReady: Bool { phase == .ready }
    var isTranscribing: Bool { activeTranscriptions > 0 }
    var isBusy: Bool { phase == .downloading || phase == .warmingUp || isTranscribing }

    /// One line for the Settings row: size, progress, warm-up, or what's wrong.
    var statusDescription: String {
        let size = ByteCountFormatter.string(fromByteCount: bytesOnDisk ?? model.approximateBytes, countStyle: .file)
        switch phase {
        case .notDownloaded:
            return "About \(size), downloaded once. Then it runs offline."
        case .downloaded:
            return "Downloaded · \(size) on this Mac. Loads when you next dictate."
        case .downloading:
            return downloadDetail ?? "Downloading… \(Int(downloadFraction * 100))%"
        case .warmingUp:
            return "Warming up on the Neural Engine…"
        case .ready:
            var line = "Ready offline · \(size) on this Mac"
            if let lastRun {
                line += String(format: " · last dictation %.2f s for %.1f s of audio",
                               lastRun.processingSeconds, lastRun.audioSeconds)
            }
            return line
        case .failed(let message):
            return message
        }
    }

    /// Re-reads what's on disk for the selected model.
    func refresh() {
        guard !isBusy else { return }
        guard isDownloaded else {
            bytesOnDisk = nil
            phase = .notDownloaded
            return
        }
        bytesOnDisk = Self.size(of: model.directory(in: modelRoot))
        phase = loadedModel == model ? .ready : .downloaded
    }

    /// Fetches the model once on launch for someone who chose Parakeet but has no copy, for example
    /// after an upgrade replaced the old model. A person who removed the model themselves is left alone.
    @discardableResult
    func downloadIfNeeded() -> Bool {
        guard phase == .notDownloaded, !isDownloaded, downloadTask == nil,
              !defaults.bool(forKey: Self.removedByUserKey) else { return false }
        download()
        return true
    }

    func download() {
        guard downloadTask == nil, !isDownloaded else {
            if isDownloaded { warmUp() }
            return
        }
        defaults.set(false, forKey: Self.removedByUserKey)
        let model = model
        let root = modelRoot
        phase = .downloading
        downloadFraction = 0
        downloadDetail = "Connecting to Hugging Face…"
        downloadTask = Task { [weak self] in
            do {
                try await ParakeetRecognizer.download(model, to: root) { [weak self] progress in
                    Task { @MainActor in self?.show(progress) }
                }
                try Task.checkCancellation()
                guard let self else { return }
                downloadTask = nil
                bytesOnDisk = Self.size(of: model.directory(in: root))
                phase = .downloaded
                warmUp()
            } catch {
                guard let self else { return }
                downloadTask = nil
                if Task.isCancelled || error is CancellationError {
                    try? FileManager.default.removeItem(at: model.directory(in: root))
                    phase = .notDownloaded
                } else {
                    phase = .failed("Download failed: \(error.localizedDescription) Try again.")
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Loads the downloaded model in the background. Safe to call repeatedly.
    @discardableResult
    func warmUp() -> Task<Bool, Never> {
        let model = model
        if let warmUpTask, warmUpModel == model { return warmUpTask }
        let root = modelRoot
        guard phase != .downloading, model.isDownloaded(in: root) else {
            if phase != .downloading { phase = .notDownloaded }
            return Task { false }
        }
        if loadedModel != model { phase = .warmingUp }
        let task = Task { [weak self, recognizer] () -> Bool in
            do {
                try await recognizer.load(model, from: root)
                self?.finishWarmUp(model, loaded: true, failure: nil)
                return true
            } catch {
                self?.finishWarmUp(model, loaded: false, failure: "Parakeet couldn't load: \(error.localizedDescription) "
                    + "Remove the model and download it again.")
                return false
            }
        }
        warmUpTask = task
        warmUpModel = model
        return task
    }

    private func finishWarmUp(_ model: ParakeetModel, loaded: Bool, failure: String?) {
        guard warmUpModel == model else { return }
        warmUpTask = nil
        warmUpModel = nil
        loadedModel = loaded ? model : nil
        guard model == self.model else { return refresh() }
        phase = failure.map(Phase.failed) ?? .ready
        if loaded { prepareVocabularyBoosting() }
    }

    /// Loads the small CTC model that spots the user's words, fetching it the first time. Dictation
    /// works without it, so a failure only means words aren't boosted.
    func prepareVocabularyBoosting() {
        guard boostingTask == nil else { return }
        boostingTask = Task { [weak self, recognizer] in
            do {
                try await recognizer.loadBoosting()
                self?.boostingTask = nil
                self?.isVocabularyBoostingReady = true
            } catch {
                self?.boostingTask = nil
                self?.isVocabularyBoostingReady = false
            }
        }
    }

    /// Recognizes recorded microphone audio. Loads the model first if it isn't loaded yet.
    /// `vocabulary` is the user's own words; Parakeet prefers them when the audio is close.
    func transcribe(_ buffers: [AVAudioPCMBuffer], vocabulary: [String] = []) async throws -> ParakeetTranscript {
        activeTranscriptions += 1
        defer { activeTranscriptions -= 1 }
        let samples = try await Task.detached(priority: .userInitiated) {
            try ParakeetRecognizer.samples(from: buffers)
        }.value
        return try await transcribe(samples: samples, vocabulary: vocabulary)
    }

    /// Recognizes audio that is already 16 kHz mono (for example a decoded file).
    func transcribe(samples: [Float], vocabulary: [String] = []) async throws -> ParakeetTranscript {
        activeTranscriptions += 1
        defer { activeTranscriptions -= 1 }
        guard await warmUp().value else { throw ParakeetRecognizerError.notLoaded }
        let transcript = try await recognizer.transcribe(samples, vocabulary: vocabulary)
        lastRun = (transcript.audioSeconds, transcript.processingSeconds)
        return transcript
    }

    func removeModel() {
        guard !isBusy else { return }
        defaults.set(true, forKey: Self.removedByUserKey)
        let directory = model.directory(in: modelRoot)
        loadedModel = nil
        Task { [weak self, recognizer] in
            await recognizer.unload()
            try? FileManager.default.removeItem(at: directory)
            self?.lastRun = nil
            self?.refresh()
        }
    }

    private func show(_ progress: ParakeetDownloadProgress) {
        guard phase == .downloading else { return }
        downloadFraction = progress.fractionDownloaded
        let percent = Int(progress.fractionDownloaded * 100)
        let total = ByteCountFormatter.string(fromByteCount: model.approximateBytes, countStyle: .file)
        switch progress.phase {
        case .listing:
            downloadDetail = "Finding the model files…"
        case .downloading(let completed, let files):
            downloadDetail = "Downloading \(percent)% of about \(total) · file \(min(completed + 1, files)) of \(files)"
        case .compiling:
            downloadDetail = "Preparing the model for this Mac's Neural Engine…"
        }
    }

    nonisolated static func size(of directory: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
