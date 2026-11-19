import AVFoundation
import Foundation
import Speech

enum LocalPermissionOutcome: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case timedOut
    case cancelled
}

/// Status-first local permission requests with a timeout and cancellation path.
enum LocalPermissionAccess {
    static func speechRecognition(timeout: TimeInterval = 30) async -> LocalPermissionOutcome {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return await waitForOutcome(timeout: timeout) { completion in
                SFSpeechRecognizer.requestAuthorization { completion(Self.speechOutcome($0)) }
            }
        @unknown default:
            return .restricted
        }
    }

    static func microphone(timeout: TimeInterval = 30) async -> LocalPermissionOutcome {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return await waitForOutcome(timeout: timeout) { completion in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    completion(granted ? .authorized : .denied)
                }
            }
        @unknown default:
            return .restricted
        }
    }

    static func waitForOutcome(
        timeout: TimeInterval,
        request: @escaping (@escaping @Sendable (LocalPermissionOutcome) -> Void) -> Void
    ) async -> LocalPermissionOutcome {
        let gate = ResolutionGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
                guard !Task.isCancelled else {
                    gate.resolve(.cancelled)
                    return
                }
                request { gate.resolve($0) }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout)) {
                    gate.resolve(.timedOut)
                }
            }
        } onCancel: {
            gate.resolve(.cancelled)
        }
    }

    private static func speechOutcome(_ status: SFSpeechRecognizerAuthorizationStatus) -> LocalPermissionOutcome {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .timedOut
        @unknown default: .restricted
        }
    }

    private final class ResolutionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<LocalPermissionOutcome, Never>?
        private var outcome: LocalPermissionOutcome?

        func install(_ continuation: CheckedContinuation<LocalPermissionOutcome, Never>) {
            lock.lock()
            let existingOutcome = outcome
            if existingOutcome == nil { self.continuation = continuation }
            lock.unlock()
            if let existingOutcome { continuation.resume(returning: existingOutcome) }
        }

        func resolve(_ outcome: LocalPermissionOutcome) {
            lock.lock()
            guard self.outcome == nil else {
                lock.unlock()
                return
            }
            self.outcome = outcome
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: outcome)
        }
    }
}
