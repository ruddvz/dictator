import Foundation
import Observation
import AVFoundation

/// Turns a recording into text with the same Parakeet model that dictation uses, on this Mac.
/// Parakeet returns plain text without word timings, so this engine has no subtitle cues.
@MainActor @Observable
final class ParakeetFileTranscriber {
    private(set) var isTranscribing = false
    private(set) var text = ""
    private(set) var cues: [SubtitleCue] = []
    private(set) var sourceName: String?
    private(set) var status: String?
    private(set) var error: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var onSessionUpdate: ((FileTranscriptionSession) -> Void)?
    @ObservationIgnored private(set) var activeSessionID = UUID()

    func transcribe(file url: URL, engine: ParakeetDictationEngine, vocabulary: [String],
                    sessionID: UUID = UUID()) {
        guard !isTranscribing else { return }
        guard engine.isDownloaded else {
            error = "The Parakeet model isn’t on this Mac yet. Download it in Settings → Dictation, then try again."
            return
        }
        generation += 1
        let currentGeneration = generation
        activeSessionID = sessionID
        isTranscribing = true
        text = ""
        cues = []
        error = nil
        sourceName = url.lastPathComponent
        status = "Reading the audio…"

        task = Task { [weak self] in
            do {
                let samples = try await Task.detached(priority: .userInitiated) {
                    try await Self.decodeSamples(from: url)
                }.value
                guard let self, currentGeneration == self.generation else { return }
                self.status = "Transcribing with Parakeet on this Mac…"
                let transcript = try await engine.transcribe(samples: samples, vocabulary: vocabulary)
                guard currentGeneration == self.generation else { return }
                self.finish(text: transcript.text, error: nil)
            } catch is CancellationError {
                return
            } catch {
                guard let self, currentGeneration == self.generation else { return }
                self.finish(text: "", error: error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard isTranscribing else { return }
        generation += 1
        task?.cancel()
        task = nil
        isTranscribing = false
        status = "Transcription cancelled."
    }

    func replaceText(_ value: String) {
        guard !isTranscribing else { return }
        text = value
    }

    func clear() {
        guard !isTranscribing else { return }
        text = ""
        cues = []
        sourceName = nil
        status = nil
        error = nil
        activeSessionID = UUID()
    }

    func restore(_ session: FileTranscriptionSession) {
        guard !isTranscribing else { return }
        text = session.text
        cues = []
        sourceName = session.sourceName
        activeSessionID = session.id
        status = "Restored from this Mac. Original audio was not copied."
        error = nil
    }

    private func finish(text value: String, error message: String?) {
        task = nil
        isTranscribing = false
        if let message {
            error = "Local transcription failed: \(message)"
            status = nil
            return
        }
        text = value
        status = value.isEmpty ? "No speech was detected in this file." : "Finished locally. The source audio was not changed."
        guard let sourceName, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSessionUpdate?(FileTranscriptionSession(
            id: activeSessionID, sourceName: sourceName, engine: .parakeet,
            languageIdentifier: "en", text: value, cues: []))
    }

    enum DecodeError: LocalizedError {
        case noAudioTrack
        var errorDescription: String? { "This file has no audio track Dictator can read." }
    }

    /// Decodes any audio or video file to the 16 kHz mono Float samples Parakeet expects.
    nonisolated static func decodeSamples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw DecodeError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? DecodeError.noAudioTrack }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                               destination: raw.baseAddress! + start * MemoryLayout<Float>.size)
            }
        }
        if reader.status == .failed { throw reader.error ?? DecodeError.noAudioTrack }
        return samples
    }
}
