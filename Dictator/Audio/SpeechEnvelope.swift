import Foundation

/// Turns the 0…1 microphone level (−60…0 dBFS) into how much someone is speaking, 0…1.
///
/// Speech is measured above a room-noise floor. The floor drops at once to any quieter moment
/// and creeps up only slowly with time, so a long sentence keeps the waveform moving instead
/// of being learned as noise, and a silent room stays flat. Time-based rather than per-sample,
/// so it behaves the same whatever rate the audio tap reports levels at.
struct SpeechEnvelope {
    /// A typical quiet room (about −45 dBFS). Used until a quieter moment is heard, so the
    /// first syllable isn't taken for the floor.
    static let assumedRoomFloor: Float = 0.25
    /// How fast the floor may rise, in level units per second.
    static let floorRisePerSecond: Float = 0.02
    /// Margin above the floor before anything counts as speech.
    static let gate: Float = 0.06
    /// Level span above the gate that maps to full scale.
    static let span: Float = 0.4

    private(set) var floor: Float?
    private var lastTime: TimeInterval?

    mutating func amount(for level: Float, at time: TimeInterval) -> Float {
        let elapsed = Float(max(0, min(0.5, time - (lastTime ?? time))))
        lastTime = time
        let current = floor ?? min(level, Self.assumedRoomFloor)
        let next = min(level, current + Self.floorRisePerSecond * elapsed)
        floor = next
        return min(1, max(0, level - next - Self.gate) / Self.span)
    }

    mutating func reset() {
        floor = nil
        lastTime = nil
    }
}
