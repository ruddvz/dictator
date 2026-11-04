import AVFoundation
import Foundation
import HushKeyParakeet
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
    var title: String {
        switch self {
        case .englishV2: "English (v2)"
        case .multilingualV3: "25 languages (v3)"
        }
    }

    /// Approximate download, measured on this Mac; the real size is shown once it's on disk.
    var approximateBytes: Int64 {
        switch self {
        case .englishV2: 451_000_000
        case .multilingualV3: 480_000_000
        }
    }

    /// Language codes the model recognizes (two-letter, from the dictation locale).
    var languageCodes: Set<String> {
        switch self {
        case .englishV2: ["en"]
        case .multilingualV3: ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
                               "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"]
        }
    }

    func supports(localeIdentifier: String) -> Bool {
        let code = Locale(identifier: localeIdentifier).language.languageCode?.identifier
            ?? String(localeIdentifier.prefix(2))
        return languageCodes.contains(code.lowercased())
    }

    /// English dictation gets the English model; other languages the multilingual one.
    static func preferred(for localeIdentifier: String) -> ParakeetModel {
        ParakeetModel.englishV2.supports(localeIdentifier: localeIdentifier) ? .englishV2 : .multilingualV3
    }
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

    var model: ParakeetModel {
        didSet {
            guard model != oldValue else { return }
            UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey)
            refresh()
        }
    }

    @ObservationIgnored private let recognizer = ParakeetRecognizer()
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var warmUpTask: Task<Bool, Never>?
    @ObservationIgnored private var warmUpModel: ParakeetModel?
    @ObservationIgnored private var loadedModel: ParakeetModel?
    @ObservationIgnored let modelRoot: URL

    static let modelKey = "parakeetModel"
    nonisolated static var defaultModelRoot: URL { AppDataDirectory.url.appending(path: "ParakeetModels", directoryHint: .isDirectory) }

    init(modelRoot: URL = ParakeetDictationEngine.defaultModelRoot,
         model: ParakeetModel? = nil, defaults: UserDefaults = .standard) {
        self.modelRoot = modelRoot
        self.model = model
            ?? defaults.string(forKey: Self.modelKey).flatMap(ParakeetModel.init(rawValue:))
            ?? .preferred(for: defaults.string(forKey: "dictationLanguage") ?? "en-US")
        refresh()
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
            return "A one-time download of about \(size). After that it runs offline on this Mac."
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

    func download() {
        guard downloadTask == nil, !isDownloaded else {
            if isDownloaded { warmUp() }
            return
        }
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
    }

    /// Recognizes recorded microphone audio. Loads the model first if it isn't loaded yet.
    func transcribe(_ buffers: [AVAudioPCMBuffer]) async throws -> ParakeetTranscript {
        activeTranscriptions += 1
        defer { activeTranscriptions -= 1 }
        let samples = try await Task.detached(priority: .userInitiated) {
            try ParakeetRecognizer.samples(from: buffers)
        }.value
        guard await warmUp().value else { throw ParakeetRecognizerError.notLoaded }
        let transcript = try await recognizer.transcribe(samples)
        lastRun = (transcript.audioSeconds, transcript.processingSeconds)
        return transcript
    }

    func removeModel() {
        guard !isBusy else { return }
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
