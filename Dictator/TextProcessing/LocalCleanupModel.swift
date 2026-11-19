import CryptoKit
import Foundation
import DictatorLlama
import Observation
import os

/// A small instruct model in GGUF form, pinned to one file by URL, size and SHA-256.
struct LocalCleanupModelFile: Equatable, Sendable {
    let title: String
    let fileName: String
    let url: URL
    let bytes: Int64
    let sha256: String
    /// Pre-filled at the start of the answer. A Qwen3 model needs an empty think block here,
    /// which is how its chat template turns thinking off.
    let assistantPrefix: String

    /// SmolLM2 360M Instruct (Apache-2.0, Hugging Face) quantized to Q4_K_M by bartowski.
    /// Picked by `docs/eval/polish-report.md`: on the polish fixtures it matched or beat
    /// Qwen3 0.6B and Qwen3.5 0.8B at half their size, and SmolLM2 135M missed more.
    static let smolLM2_360M = LocalCleanupModelFile(
        title: "SmolLM2 360M",
        fileName: "SmolLM2-360M-Instruct-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/7be6f65f1db715fe5dc5a4634c0d459b4eed42ec/SmolLM2-360M-Instruct-Q4_K_M.gguf")!,
        bytes: 270_590_880,
        sha256: "2fa3f013dcdd7b99f9b237717fa0b12d75bbb89984cc1274be1471a465bac9c2",
        assistantPrefix: "")

    static let `default` = smolLM2_360M
}

/// The optional on-device model that makes Polished work on Macs without Apple Intelligence
/// (macOS 14–15, or 26 with it turned off). Nothing is downloaded until you choose Download in
/// Style or Settings; after that it runs offline with llama.cpp. Apple's model stays first choice
/// where it's available, and both go through the same delete-only check
/// (`DictationSmartCleanup.isSafeCleanup`), so a small model can't reword your text.
@MainActor @Observable
final class LocalCleanupModel {
    enum Phase: Equatable {
        case notDownloaded
        case downloading
        case downloaded
        case loading
        case ready
        case failed(String)
    }

    static let shared = LocalCleanupModel()

    private(set) var phase: Phase = .notDownloaded
    private(set) var downloadFraction: Double = 0
    /// The last polish: how long the model took, for the Settings row.
    private(set) var lastRunSeconds: Double?

    let file: LocalCleanupModelFile
    @ObservationIgnored let root: URL
    @ObservationIgnored private let runner = LlamaRunner()
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Bool, Never>?
    @ObservationIgnored private var idleUnloadTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.ruddvz.dictator", category: "local-cleanup")

    /// Frees the model's memory after this long without a dictation; it reloads in under a second.
    static let idleUnloadDelay: Duration = .seconds(10 * 60)

    nonisolated static var defaultRoot: URL {
        AppDataDirectory.url.appending(path: "CleanupModels", directoryHint: .isDirectory)
    }

    init(file: LocalCleanupModelFile = .default, root: URL = LocalCleanupModel.defaultRoot) {
        self.file = file
        self.root = root
        refresh()
    }

    var fileURL: URL { root.appending(path: file.fileName) }
    private var partialURL: URL { root.appending(path: file.fileName + ".part") }
    var isDownloaded: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
    var isBusy: Bool { phase == .downloading || phase == .loading }

    /// One line for the Settings and Style rows.
    var statusDescription: String {
        let size = ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file)
        switch phase {
        case .notDownloaded:
            return "Polished needs Apple Intelligence or a small on-device model: \(file.title), a one-time "
                + "download of \(size). It only deletes fillers and fixes punctuation, offline."
        case .downloading:
            return "Downloading \(file.title)… \(Int(downloadFraction * 100))% of \(size)"
        case .downloaded:
            return "\(file.title) · \(size) on this Mac. Loads when you next dictate."
        case .loading:
            return "Loading \(file.title)…"
        case .ready:
            var line = "\(file.title) ready offline · \(size) on this Mac"
            if let lastRunSeconds { line += String(format: " · last polish %.2f s", lastRunSeconds) }
            return line
        case .failed(let message):
            return message
        }
    }

    func refresh() {
        guard !isBusy else { return }
        if !isDownloaded { phase = .notDownloaded } else if phase != .ready { phase = .downloaded }
    }

    // MARK: Download

    func download() {
        guard downloadTask == nil, !isDownloaded else { return }
        let file = file, destination = fileURL, partial = partialURL, root = root
        phase = .downloading
        downloadFraction = 0
        downloadTask = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try await ModelDownloader.download(file.url, to: partial) { fraction in
                    Task { @MainActor in self?.showProgress(fraction) }
                }
                try Task.checkCancellation()
                try await Task.detached(priority: .utility) {
                    try ModelDownloader.verify(partial, bytes: file.bytes, sha256: file.sha256)
                }.value
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: partial, to: destination)
                self?.finishDownload(failure: nil)
            } catch {
                try? FileManager.default.removeItem(at: partial)
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                self?.finishDownload(failure: cancelled ? nil : "Download failed: \(error.localizedDescription) Try again.")
            }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    private func showProgress(_ fraction: Double) {
        guard phase == .downloading else { return }
        downloadFraction = fraction
    }

    private func finishDownload(failure: String?) {
        downloadTask = nil
        phase = .notDownloaded
        if let failure { phase = .failed(failure) } else { refresh() }
    }

    func removeModel() {
        guard !isBusy else { return }
        idleUnloadTask?.cancel()
        let url = fileURL
        Task { [weak self, runner] in
            await runner.unload()
            try? FileManager.default.removeItem(at: url)
            self?.lastRunSeconds = nil
            self?.phase = .notDownloaded
        }
    }

    // MARK: Load and polish

    /// Loads the model in the background, e.g. while you're still talking. Safe to call repeatedly.
    @discardableResult
    func warmUp() -> Task<Bool, Never> {
        if let loadTask { return loadTask }
        if phase == .ready { return Task { true } }
        guard isDownloaded, phase != .downloading else { return Task { false } }
        phase = .loading
        let path = fileURL.path
        let task = Task { [weak self, runner] () -> Bool in
            do {
                try await runner.load(path: path)
                self?.finishLoad(failure: nil)
                return true
            } catch {
                self?.finishLoad(failure: "\(error.localizedDescription) Remove the model and download it again.")
                return false
            }
        }
        loadTask = task
        return task
    }

    private func finishLoad(failure: String?) {
        loadTask = nil
        phase = failure.map(Phase.failed) ?? .ready
        if failure == nil { scheduleIdleUnload() }
    }

    /// The model's raw answer for `prompt`, or nil when it isn't downloaded, fails, or is cancelled.
    func respond(system: String, examples: [(user: String, assistant: String)] = [], user: String,
                 maxTokens: Int) async -> String? {
        guard await warmUp().value, !Task.isCancelled else { return nil }
        idleUnloadTask?.cancel()
        defer { scheduleIdleUnload() }
        let prompt = LlamaRunner.chatML(system: system, examples: examples, user: user,
                                       assistantPrefix: file.assistantPrefix)
        let start = ContinuousClock.now
        do {
            let answer = try await runner.generate(prompt: prompt, maxTokens: maxTokens)
            let elapsed = ContinuousClock.now - start
            lastRunSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            return answer
        } catch {
            if (error as? LlamaRunnerError) != .cancelled {
                log.error("Local cleanup failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    /// Frees every loaded model synchronously; call when the app quits.
    static func unloadAllBeforeExit() {
        shared.idleUnloadTask?.cancel()
        LlamaRunner.unloadAll()
        if shared.phase == .ready { shared.phase = .downloaded }
    }

    /// Frees this model synchronously.
    func unloadBeforeExit() {
        idleUnloadTask?.cancel()
        runner.unloadNow()
        if phase == .ready { phase = .downloaded }
    }

    /// Stops a running answer, e.g. when the polish pass ran out of time.
    func cancelResponse() { runner.cancel() }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self, runner] in
            try? await Task.sleep(for: Self.idleUnloadDelay)
            guard !Task.isCancelled, let self, self.phase == .ready, self.loadTask == nil else { return }
            await runner.unload()
            if self.phase == .ready { self.phase = .downloaded }
        }
    }
}

/// Downloads one file with progress, then checks its size and SHA-256.
enum ModelDownloader {
    static func download(_ url: URL, to destination: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    static func verify(_ file: URL, bytes: Int64, sha256: String) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
        guard size == bytes else { throw ModelDownloadError.wrongSize }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw ModelDownloadError.checksumMismatch }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        let progress: @Sendable (Double) -> Void
        var continuation: CheckedContinuation<Void, Error>?
        private var moveError: Error?

        init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
            self.destination = destination
            self.progress = progress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // The temporary file is deleted when this returns, so move it now.
            if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                moveError = ModelDownloadError.httpStatus(status)
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                moveError = error
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error ?? moveError { continuation?.resume(throwing: error) } else { continuation?.resume() }
            continuation = nil
        }
    }
}

enum ModelDownloadError: LocalizedError {
    case httpStatus(Int)
    case wrongSize
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status): "The server answered \(status)."
        case .wrongSize: "The file is the wrong size."
        case .checksumMismatch: "The file didn't match its checksum."
        }
    }
}
