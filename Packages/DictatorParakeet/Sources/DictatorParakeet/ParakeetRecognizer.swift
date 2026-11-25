@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// Dictator's single English streaming Parakeet model, run locally through FluidAudio/Core ML.
public enum ParakeetModel: String, CaseIterable, Sendable, Identifiable {
    /// NVIDIA's English Parakeet Unified 0.6B checkpoint, exposed by FluidAudio 0.18.4.
    case englishUnified = "parakeet-unified-en-0.6b-coreml"

    public var id: String { rawValue }

    public var configuration: UnifiedConfig { UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 7) }
    public var family: UnifiedModelFamily { .parakeetEnglish }
    public var repo: Repo { family.repo }

    /// FluidAudio's Hugging Face cache directory for this single checkpoint.
    public var folderName: String { repo.folderName }

    public func directory(in root: URL) -> URL {
        root.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// Files required for the selected 1.12-second streaming configuration only.
    public var requiredFiles: Set<String> {
        [
            family.streamingEncoderFile(precision: .int8, contextSuffix: configuration.contextSuffix),
            family.decoderFile,
            family.jointDecisionFile,
            family.vocab,
        ]
    }

    /// True when every model bundle and shared file for this tier is present.
    public func isDownloaded(in root: URL) -> Bool {
        requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: directory(in: root).appending(path: $0).path) }
    }
}

/// One step of a model download, for the setup progress bar.
public struct ParakeetDownloadProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case listing
        case downloading(completedFiles: Int, totalFiles: Int)
        /// Core ML compiles the model for this Mac's Neural Engine after the files arrive.
        case compiling(String)
    }

    /// Fraction of the bytes downloaded so far, in [0, 1].
    public var fractionDownloaded: Double
    public var phase: Phase
}

public struct ParakeetTranscript: Sendable {
    public var text: String
    public var confidence: Float
    /// Seconds of audio that were recognized.
    public var audioSeconds: TimeInterval
    /// Seconds spent recognizing, measured around the model call.
    public var processingSeconds: TimeInterval
}

public enum ParakeetRecognizerError: LocalizedError {
    case notLoaded
    case noAudio

    public var errorDescription: String? {
        switch self {
        case .notLoaded: "The Parakeet model isn't loaded."
        case .noAudio: "There was no audio to recognize."
        }
    }
}

/// Downloads, loads and runs the single English Parakeet Unified streaming tier. Audio never
/// leaves the Mac; only the selected Core ML model files are fetched from Hugging Face.
public actor ParakeetRecognizer {
    public static let sampleRate = 16_000

    private var manager: StreamingUnifiedAsrManager?
    public private(set) var loadedModel: ParakeetModel?
    private var loadedRoot: URL?
    private var ctcModels: CtcModels?
    private var ctcTokenizer: CtcTokenizer?
    /// Key of the vocabulary configured on `manager`, or nil when none is. FluidAudio can add a
    /// vocabulary to a manager but not remove it, so clearing one rebuilds the manager.
    private var boostedKey: String?
    public static let maximumBoostedTerms = 100

    public init() {}

    /// Downloads the model's Core ML files into `root`. Does nothing when they are already there.
    public static func download(_ model: ParakeetModel, to root: URL,
                                progress: @escaping @Sendable (ParakeetDownloadProgress) -> Void) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tracker = DownloadTracker(report: progress)
        let encoder = model.family.streamingEncoderFile(
            precision: .int8, contextSuffix: model.configuration.contextSuffix)
        try await ModelHub.download(model.repo, to: root,
                                    additionalModelNames: [encoder],
                                    progressHandler: { tracker.update($0) })
    }

    /// Loads the model and runs it once on silence, so the first dictation doesn't pay for
    /// Core ML's Neural Engine warm-up.
    public func load(_ model: ParakeetModel, from root: URL, force: Bool = false) async throws {
        if !force, loadedModel == model, manager != nil { return }
        await unload()
        let manager = StreamingUnifiedAsrManager(config: model.configuration)
        try await manager.loadModels(to: root)
        let silence = try Self.buffer(from: [Float](repeating: 0, count: model.configuration.chunkSamples + model.configuration.rightSamples))
        try await manager.appendAudio(silence)
        try await manager.processBufferedAudio()
        _ = try await manager.finish()
        try await manager.reset()
        self.manager = manager
        loadedModel = model
        loadedRoot = root
        boostedKey = nil
    }

    // MARK: - Custom vocabulary

    /// True when FluidAudio's small CTC model (used to spot the user's words in the audio) is on disk.
    public static var boostingModelIsDownloaded: Bool {
        CtcModels.modelsExist(at: CtcModels.defaultCacheDirectory())
    }

    public var isBoostingReady: Bool { ctcModels != nil && ctcTokenizer != nil }

    /// Downloads (once) and loads the CTC model that lets Parakeet prefer the user's vocabulary.
    public func loadBoosting() async throws {
        guard !isBoostingReady else { return }
        let models = try await CtcModels.downloadAndLoad()
        let tokenizer = try await CtcTokenizer.load(from: CtcModels.defaultCacheDirectory())
        ctcModels = models
        ctcTokenizer = tokenizer
    }

    /// The terms worth boosting: trimmed, unique, at least three letters, capped.
    public static func boostableTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard trimmed.filter(\.isLetter).count >= 3, seen.insert(key).inserted else { continue }
            result.append(trimmed)
            if result.count == maximumBoostedTerms { break }
        }
        return result
    }

    /// Makes `manager` boost exactly `terms`. Boosting never blocks dictation: any failure leaves
    /// the plain transcript.
    private func applyBoosting(_ terms: [String], to manager: StreamingUnifiedAsrManager) async -> StreamingUnifiedAsrManager {
        let terms = Self.boostableTerms(terms)
        let key = terms.map { $0.lowercased() }.sorted().joined(separator: "\n")
        if terms.isEmpty {
            // A vocabulary configured earlier can't be removed; start from a fresh manager.
            guard boostedKey != nil, let model = loadedModel, let root = loadedRoot else { return manager }
            try? await load(model, from: root, force: true)
            return self.manager ?? manager
        }
        guard key != boostedKey, let ctcModels, let ctcTokenizer else { return manager }
        let tokenized = terms.compactMap { term -> CustomVocabularyTerm? in
            let ids = ctcTokenizer.encode(term)
            return ids.isEmpty ? nil : CustomVocabularyTerm(text: term, ctcTokenIds: ids)
        }
        guard !tokenized.isEmpty else { return manager }
        do {
            try await manager.configureVocabularyBoosting(
                vocabulary: CustomVocabularyContext(terms: tokenized), ctcModels: ctcModels)
            boostedKey = key
        } catch {
            boostedKey = nil
        }
        return manager
    }

    public func unload() async {
        if let manager { await manager.cleanup() }
        manager = nil
        loadedModel = nil
    }

    /// Recognizes 16 kHz mono samples.
    /// `vocabulary` lists words and names to prefer when the audio is close to one of them.
    public func transcribe(_ samples: [Float], vocabulary: [String] = []) async throws -> ParakeetTranscript {
        guard let loaded = manager else { throw ParakeetRecognizerError.notLoaded }
        guard !samples.isEmpty else { throw ParakeetRecognizerError.noAudio }
        let started = ContinuousClock.now
        let manager = await applyBoosting(vocabulary, to: loaded)
        try await manager.reset()
        try await manager.appendAudio(Self.buffer(from: samples))
        try await manager.processBufferedAudio()
        let text = try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        let timings = await manager.consumeTokenTimings()
        let elapsed = ContinuousClock.now - started
        return ParakeetTranscript(
            text: text,
            confidence: timings.isEmpty ? 0 : timings.reduce(Float(0)) { $0 + $1.confidence } / Float(timings.count),
            audioSeconds: Double(samples.count) / Double(Self.sampleRate),
            processingSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    private static func buffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(Self.sampleRate), channels: 1) else {
            throw ParakeetRecognizerError.noAudio
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?.pointee else { throw ParakeetRecognizerError.noAudio }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            channel.update(from: baseAddress, count: samples.count)
        }
        return buffer
    }

    /// Joins microphone buffers and converts them to 16 kHz mono, as Parakeet expects.
    /// Buffers in a different format from the first are skipped.
    public static func samples(from buffers: [AVAudioPCMBuffer]) throws -> [Float] {
        guard let first = buffers.first(where: { $0.frameLength > 0 }) else { return [] }
        let format = first.format
        let matching = buffers.filter { $0.format == format && $0.frameLength > 0 }
        let frames = matching.reduce(0) { $0 + AVAudioFrameCount($1.frameLength) }
        guard let joined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return [] }
        // Interleaved audio has one buffer holding every channel, planar audio one buffer per
        // channel; either way each buffer's frames are `mBytesPerFrame` wide.
        let frameBytes = Int(format.streamDescription.pointee.mBytesPerFrame)
        for buffer in matching {
            let offset = Int(joined.frameLength) * frameBytes
            let byteCount = Int(buffer.frameLength) * frameBytes
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let target = UnsafeMutableAudioBufferListPointer(joined.mutableAudioBufferList)
            for index in 0..<min(source.count, target.count) {
                guard let from = source[index].mData, let to = target[index].mData else { continue }
                (to + offset).copyMemory(from: from, byteCount: byteCount)
            }
            joined.frameLength += buffer.frameLength
        }
        return try AudioConverter().resampleBuffer(joined)
    }
}

/// Turns FluidAudio's per-operation progress into a byte fraction that only moves forward.
private final class DownloadTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var best = 0.0
    private let report: @Sendable (ParakeetDownloadProgress) -> Void

    init(report: @escaping @Sendable (ParakeetDownloadProgress) -> Void) {
        self.report = report
    }

    func update(_ progress: DownloadProgress) {
        let snapshot: ParakeetDownloadProgress = lock.withLock {
            switch progress.phase {
            case .listing:
                return ParakeetDownloadProgress(fractionDownloaded: best, phase: .listing)
            case .downloading(let completed, let total):
                // FluidAudio gives the download half of each operation (compiling is the rest).
                best = max(best, min(1, progress.fractionCompleted * 2))
                return ParakeetDownloadProgress(fractionDownloaded: best,
                                                phase: .downloading(completedFiles: completed, totalFiles: total))
            case .compiling(let name):
                best = 1
                return ParakeetDownloadProgress(fractionDownloaded: 1, phase: .compiling(name))
            }
        }
        report(snapshot)
    }
}
