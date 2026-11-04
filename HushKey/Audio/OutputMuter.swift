import AudioToolbox
import CoreAudio
import Foundation

/// Silences the Mac's sound output while you dictate, so music or a video playing in the
/// background doesn't talk over you (or into the mic), then puts it back.
///
/// It only undoes what it did: output that was already muted stays muted, and if you change the
/// volume or mute while dictating, your change wins. The device it muted is remembered on disk, so
/// a crash or force-quit mid-dictation is undone on the next launch.
@MainActor
final class OutputMuter {
    private struct Muted: Codable {
        var deviceID: AudioDeviceID
        /// Whether the device's mute switch was used; otherwise its volume was set to 0.
        var usedMuteSwitch: Bool
        var previousVolume: Float32
    }

    private static let storageKey = "outputMuterPending"
    private var pendingMute: Task<Void, Never>?

    init() {
        restoreAfterUnexpectedExit()
    }

    /// Mutes output after `delay`, so the start cue can finish playing first.
    func mute(after delay: TimeInterval) {
        pendingMute?.cancel()
        pendingMute = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.muteNow()
        }
    }

    func restore() {
        pendingMute?.cancel()
        pendingMute = nil
        guard let muted = stored else { return }
        stored = nil
        if muted.usedMuteSwitch {
            // Still muted means nobody touched it; anything else is the user's own choice.
            if Self.isMuted(muted.deviceID) == true { Self.setMuted(false, on: muted.deviceID) }
        } else if let volume = Self.volume(of: muted.deviceID), volume < 0.001 {
            Self.setVolume(muted.previousVolume, on: muted.deviceID)
        }
    }

    private func muteNow() {
        guard stored == nil, let device = Self.defaultOutputDevice() else { return }
        if let isMuted = Self.isMuted(device) {
            guard !isMuted, Self.setMuted(true, on: device) else { return }
            stored = Muted(deviceID: device, usedMuteSwitch: true, previousVolume: 0)
        } else if let volume = Self.volume(of: device), volume > 0.001 {
            guard Self.setVolume(0, on: device) else { return }
            stored = Muted(deviceID: device, usedMuteSwitch: false, previousVolume: volume)
        }
    }

    private func restoreAfterUnexpectedExit() {
        guard stored != nil else { return }
        restore()
    }

    private var stored: Muted? {
        get {
            UserDefaults.standard.data(forKey: Self.storageKey)
                .flatMap { try? JSONDecoder().decode(Muted.self, from: $0) }
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
            }
        }
    }

    // MARK: Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func isSettable(_ address: inout AudioObjectPropertyAddress, on device: AudioDeviceID) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    /// `nil` when the device has no mute switch HushKey can use.
    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = address(kAudioDevicePropertyMute)
        guard isSettable(&address, on: device) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyMute)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func volume(of device: AudioDeviceID) -> Float32? {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard isSettable(&address, on: device) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    private static func setVolume(_ volume: Float32, on device: AudioDeviceID) -> Bool {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}
