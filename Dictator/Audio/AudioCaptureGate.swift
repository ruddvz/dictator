import Observation

/// Ensures dictation and meeting notes never open competing microphone engines.
@MainActor @Observable
final class AudioCaptureGate {
    enum Owner: Equatable {
        case dictation
        case meeting
    }

    private(set) var owner: Owner?

    @discardableResult
    func claim(_ requestedOwner: Owner) -> Bool {
        guard owner == nil else { return false }
        owner = requestedOwner
        return true
    }

    func release(_ releasingOwner: Owner) {
        guard owner == releasingOwner else { return }
        owner = nil
    }
}
