import AVFoundation

/// Short, quiet cues that replace on-screen confirmations: one when the mic opens, one when
/// the words land, one when something needs attention. Synthesised here (soft sine notes with
/// a bell-like decay) so they're HushKey's own and no audio files ship with the app.
enum DictationCue: CaseIterable {
    /// Rising two-note open: the mic is listening.
    case start
    /// A soft bell chord: the text was typed, or is ready to copy.
    case success
    /// Two falling notes, lower: dictation didn't go through.
    case error

    /// (frequency Hz, start s, length s, gain) for each note.
    fileprivate var notes: [(Double, Double, Double, Double)] {
        switch self {
        case .start: [(587.33, 0, 0.11, 0.8), (880.0, 0.07, 0.16, 0.7)]
        case .success: [(1046.5, 0, 0.26, 0.6), (1568.0, 0.012, 0.22, 0.35)]
        case .error: [(466.16, 0, 0.13, 0.8), (349.23, 0.11, 0.2, 0.8)]
        }
    }

    static let sampleRate = 44_100.0

    /// How long the cue plays, in seconds.
    var duration: TimeInterval { notes.map { $0.1 + $0.2 }.max() ?? 0 }

    /// Mono samples in −1…1. Every note fades in over 4 ms and decays to silence, so the cue
    /// never clicks at either end.
    var samples: [Float] {
        let length = duration
        var output = [Float](repeating: 0, count: Int(length * Self.sampleRate) + 1)
        for (frequency, start, duration, gain) in notes {
            let first = Int(start * Self.sampleRate)
            let count = Int(duration * Self.sampleRate)
            for index in 0..<count where first + index < output.count {
                let t = Double(index) / Self.sampleRate
                let attack = min(1, t / 0.004)
                let decay = pow(1 - Double(index) / Double(count), 3)
                // A quiet octave above gives the sine a little warmth without sounding like a beep.
                let wave = sin(2 * .pi * frequency * t) + 0.18 * sin(4 * .pi * frequency * t)
                output[first + index] += Float(wave * attack * decay * gain * 0.32)
            }
        }
        return output
    }

    /// 16-bit PCM WAV of `samples`, for `AVAudioPlayer(data:)`.
    var wavData: Data {
        let pcm = samples.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) }
        let rate = UInt32(Self.sampleRate)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + pcm.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(rate); append(rate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(pcm.count * 2))
        pcm.forEach { append($0) }
        return data
    }
}

/// Plays `DictationCue`s. Players are built once and reused so a cue starts without delay, and
/// they play on their own queue: starting audio output can take 30–100 ms, which on the main
/// thread held up the pill's first listening frame.
final class DictationSoundPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ruddvz.hushkey.cues", qos: .userInteractive)
    /// Only touched on `queue`.
    private var players: [DictationCue: AVAudioPlayer] = [:]

    func play(_ cue: DictationCue, volume: Float = 0.6) {
        queue.async { [self] in
            let player = players[cue] ?? {
                let made = try? AVAudioPlayer(data: cue.wavData)
                made?.prepareToPlay()
                players[cue] = made
                return made
            }()
            guard let player else { return }
            player.volume = volume
            player.currentTime = 0
            player.play()
        }
    }
}
