import AVFoundation
import CoreAudio
import Observation

/// Captures app output through a private Core Audio tap. The source audio is streamed only
/// into the local speech recognizer and is never written to disk.
@MainActor @Observable
final class SystemAudioService {
    private(set) var isRunning = false
    private(set) var level: Float = 0
    private(set) var error: String?

    @ObservationIgnored let sink = AudioSink()
    @ObservationIgnored private var tapID: AudioObjectID?
    @ObservationIgnored private var aggregateID: AudioObjectID?
    @ObservationIgnored private var engine: AVAudioEngine?

    func start() {
        guard !isRunning else { return }
        error = nil

        guard #available(macOS 14.2, *) else {
            error = "System audio capture requires macOS 14.2 or later. Choose Microphone instead."
            return
        }

        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "HushKey Meeting Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var createdTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &createdTap)
        guard tapStatus == noErr else {
            error = Self.statusMessage("create the system audio tap", status: tapStatus)
            return
        }
        tapID = createdTap

        guard let tapUID = Self.uid(for: createdTap) else {
            error = "macOS created an audio tap but did not return its identifier."
            tearDown()
            return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "HushKey Meeting Audio",
            kAudioAggregateDeviceUIDKey: "com.ruddvz.hushkey.meeting.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: 1
            ]],
            kAudioAggregateDeviceTapAutoStartKey: 1
        ]
        var createdAggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary,
                                                                  &createdAggregate)
        guard aggregateStatus == noErr else {
            error = Self.statusMessage("prepare a private audio input", status: aggregateStatus)
            tearDown()
            return
        }
        aggregateID = createdAggregate

        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let audioUnit = input.audioUnit else {
            error = "macOS did not provide an audio input for the system audio tap."
            tearDown()
            return
        }
        var deviceID = createdAggregate
        let deviceStatus = AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard deviceStatus == noErr else {
            error = Self.statusMessage("connect the private audio input", status: deviceStatus)
            tearDown()
            return
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            error = "The system audio source has no usable audio format."
            tearDown()
            return
        }

        sink.setLevelHandler { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(for: sink))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.error = "System audio capture could not start. Check System Settings › Privacy & Security › System Audio Recording. \(error.localizedDescription)"
            sink.setLevelHandler(nil)
            tearDown()
            return
        }

        self.engine = engine
        isRunning = true
    }

    func stop() {
        guard isRunning || tapID != nil || aggregateID != nil else { return }
        tearDown()
        isRunning = false
        level = 0
    }

    private func tearDown() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
        }
        sink.setLevelHandler(nil)

        if let aggregateID {
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            self.aggregateID = nil
        }
        if #available(macOS 14.2, *), let tapID {
            _ = AudioHardwareDestroyProcessTap(tapID)
            self.tapID = nil
        }
    }

    private static func uid(for tapID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func statusMessage(_ operation: String, status: OSStatus) -> String {
        "Could not \(operation) (Core Audio error \(status)). Check System Settings › Privacy & Security › System Audio Recording."
    }

    nonisolated private static func tapBlock(for sink: AudioSink) -> AVAudioNodeTapBlock {
        { buffer, time in sink.dispatch(buffer, time) }
    }
}
