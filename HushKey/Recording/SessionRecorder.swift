import AVFoundation
import AppKit
import Observation

/// Records synchronized motion CSV + optionally enabled microphone audio + labelled segment events for offline
/// analysis (normal speech vs. whisper vs. silent mouthing).
///
/// Output: ~/Documents/HushKey/Sessions/<timestamp>-<condition>/
///   motion.csv  — every headphone-motion sample, t relative to session start
///   audio.caf   — microphone audio only after explicit opt-in and while the mic is running
///   events.csv  — captured segments with their label / prediction
///   meta.json   — condition, prompt, clock offsets
@MainActor @Observable
final class SessionRecorder {
    enum Condition: String, CaseIterable, Identifiable, Codable {
        case normal = "Normal voice"
        case whisper = "Whisper"
        case silent = "Silent mouthing"
        var id: String { rawValue }
        var slug: String {
            switch self {
            case .normal: "normal"
            case .whisper: "whisper"
            case .silent: "silent"
            }
        }
    }

    var condition: Condition = .silent
    var prompt = ""
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var motionCount = 0
    private(set) var eventCount = 0
    private(set) var lastSessionURL: URL?
    private(set) var error: String?

    static var root: URL {
        URL.documentsDirectory.appending(path: "HushKey/Sessions", directoryHint: .isDirectory)
    }

    private let rootURL: URL

    init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? Self.root
    }

    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var startUptime: TimeInterval = 0
    @ObservationIgnored private var motionHandle: FileHandle?
    @ObservationIgnored private var eventsHandle: FileHandle?
    @ObservationIgnored private var audioWriter: AudioFileWriter?
    @ObservationIgnored private var sinkID: UUID?
    @ObservationIgnored private weak var sink: AudioSink?
    @ObservationIgnored private var audioDeviceName: String?
    @ObservationIgnored private var microphoneAudioRequested = false

    func start(audio: AudioService, includeMicrophoneAudio: Bool = false) {
        guard !isRecording else { return }
        error = nil
        microphoneAudioRequested = includeMicrophoneAudio
        let dir = rootURL.appending(path: Self.sessionDirectoryName(date: Date(), id: UUID(), condition: condition),
                                    directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            motionHandle = try Self.makeFile(dir.appending(path: "motion.csv"), header: MotionSample.csvHeader)
            eventsHandle = try Self.makeFile(dir.appending(path: "events.csv"), header: "start,end,kind,label,confidence")
        } catch {
            self.error = error.localizedDescription
            return
        }

        directory = dir
        startUptime = ProcessInfo.processInfo.systemUptime
        startedAt = Date()
        motionCount = 0
        eventCount = 0

        if Self.shouldCaptureAudio(includeMicrophoneAudio: includeMicrophoneAudio,
                                   microphoneIsRunning: audio.isRunning) {
            let writer = AudioFileWriter(url: dir.appending(path: "audio.caf"))
            audioWriter = writer
            sink = audio.sink
            sinkID = audio.sink.add { buffer, time in writer.write(buffer, time) }
            audioDeviceName = audio.activeDeviceName
        }
        isRecording = true
    }

    func stop() {
        guard isRecording, let directory else { return }
        isRecording = false
        if let sinkID { sink?.remove(sinkID) }
        sinkID = nil
        let audioInfo = audioWriter?.finish()
        audioWriter = nil
        try? motionHandle?.close()
        try? eventsHandle?.close()
        motionHandle = nil
        eventsHandle = nil

        let meta: [String: Any] = [
            "condition": condition.rawValue,
            "prompt": prompt,
            "startedAt": startedAt?.ISO8601Format() ?? "",
            "startUptime": startUptime,
            "durationSeconds": ProcessInfo.processInfo.systemUptime - startUptime,
            "motionSamples": motionCount,
            "events": eventCount,
            "audioDevice": audioDeviceName ?? NSNull(),
            "microphoneAudioRequested": microphoneAudioRequested,
            "audioSampleRate": audioInfo?.sampleRate ?? NSNull(),
            "audioStartOffsetSeconds": audioInfo?.firstHostSeconds.map { $0 - startUptime } ?? NSNull(),
            "note": "Motion t and audioStartOffsetSeconds are relative to startUptime (seconds since boot).",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appending(path: "meta.json"), options: .atomic)
        }
        lastSessionURL = directory
        self.directory = nil
    }

    static func shouldCaptureAudio(includeMicrophoneAudio: Bool, microphoneIsRunning: Bool) -> Bool {
        includeMicrophoneAudio && microphoneIsRunning
    }

    static func sessionDirectoryName(date: Date, id: UUID, condition: Condition) -> String {
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
            .replacingOccurrences(of: ":", with: "")
        return "\(stamp)-\(id.uuidString)-\(condition.slug)"
    }

    func deleteAllSessions() throws {
        guard !isRecording else { throw CocoaError(.userCancelled) }
        if FileManager.default.fileExists(atPath: Self.root.path) {
            try FileManager.default.removeItem(at: Self.root)
        }
        lastSessionURL = nil
    }

    func exportAllSessions() throws -> URL? {
        guard FileManager.default.fileExists(atPath: Self.root.path) else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Sessions"
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        let name = "HushKey-Sessions-\(Date.now.formatted(.iso8601.year().month().day()))"
        let target = destination.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: Self.root, to: target)
        return target
    }

    func record(_ sample: MotionSample) {
        guard isRecording else { return }
        motionHandle?.write(Data((sample.csvRow(relativeTo: startUptime) + "\n").utf8))
        motionCount += 1
    }

    func logEvent(_ segment: [MotionSample], kind: String, label: String, confidence: Double?) {
        guard isRecording, let first = segment.first, let last = segment.last else { return }
        let row = [
            String(format: "%.4f", first.t - startUptime),
            String(format: "%.4f", last.t - startUptime),
            kind,
            label.replacingOccurrences(of: ",", with: " "),
            confidence.map { String(format: "%.3f", $0) } ?? "",
        ].joined(separator: ",")
        eventsHandle?.write(Data((row + "\n").utf8))
        eventCount += 1
    }

    private static func makeFile(_ url: URL, header: String) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path, contents: Data((header + "\n").utf8)) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }
}

/// Writes tap buffers to disk from the audio thread.
private final class AudioFileWriter: @unchecked Sendable {
    struct Info {
        var sampleRate: Double
        var firstHostSeconds: Double?
    }

    private let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var info: Info?
    private var failed = false

    init(url: URL) {
        self.url = url
    }

    func write(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        lock.withLock {
            guard !failed else { return }
            if file == nil {
                do {
                    let format = buffer.format
                    file = try AVAudioFile(
                        forWriting: url, settings: format.settings,
                        commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                    info = Info(
                        sampleRate: format.sampleRate,
                        firstHostSeconds: time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : nil)
                } catch {
                    failed = true
                    return
                }
            }
            try? file?.write(from: buffer)
        }
    }

    func finish() -> Info? {
        lock.withLock {
            file = nil
            return info
        }
    }
}
