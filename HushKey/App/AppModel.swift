import AppKit
import AVFoundation
import Speech
import Observation
import os
import ServiceManagement
import UniformTypeIdentifiers

/// What the last silent capture did, for the small HUD shown while another app is in front.
struct SilentCaptureFeedback: Equatable {
    enum Kind: Equatable { case typed, notTyped, unsure, ignored, saved, problem }
    var id = UUID()
    var kind: Kind
    var text: String
}

struct DecodedWord: Identifiable, Hashable {
    let id = UUID()
    var prediction: Prediction
    var text: String { prediction.best?.label ?? "?" }
}

@MainActor @Observable
final class AppModel {
    enum Screen: String, CaseIterable, Identifiable {
        case dictation = "Dictation"
        case transforms = "Transforms"
        case files = "Transcribe files"
        case meetings = "Meeting notes"
        case setup = "Setup"
        case train = "Train"
        case evaluate = "Evaluate"
        case use = "Silent Use"
        case personalization = "Snippets & Vocabulary"
        case style = "Style"
        case insights = "Insights"
        case settings = "Settings & Data"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .dictation: "mic"
            case .transforms: "wand.and.stars"
            case .files: "doc.text"
            case .meetings: "person.2.wave.2"
            case .setup: "headphones"
            case .train: "square.stack.3d.up"
            case .evaluate: "chart.bar.xaxis"
            case .use: "text.bubble"
            case .personalization: "character.book.closed"
            case .style: "textformat"
            case .insights: "chart.bar"
            case .settings: "gearshape"
            }
        }
        /// Short label for the sidebar; `rawValue` stays the full page name.
        var sidebarTitle: String {
            switch self {
            case .files: "Files"
            case .personalization: "Vocabulary"
            case .settings: "Settings"
            case .setup: "Connect"
            default: rawValue
            }
        }
    }

    enum InsertionOutputRoute: Equatable {
        case dictation
        case silentPrediction
        case unavailable
    }

    let motion = HeadphoneMotionService()
    let audio = AudioService()
    let transcriber = MicTranscriber()
    /// Parakeet: an optional, downloaded dictation engine that runs when the key is released.
    let parakeet = ParakeetDictationEngine()
    let captureGate: AudioCaptureGate
    let meetingNotes: MeetingNotesService
    let localTransformService = LocalTransformService()
    let fileTranscriber = LocalFileTranscriber()
    let whisperFileTranscriber = WhisperKitFileTranscriber()
    let fileTranscriptionWorkspace = FileTranscriptionWorkspace()
    let insertion = TextInsertionService()
    let capture = CaptureController()
    let recorder: SessionRecorder

    var screen: Screen = .dictation {
        didSet {
            if oldValue != screen { capture.cancel() }
            syncCaptureMode()
            updateMotionActivity()
        }
    }

    // MARK: Training

    private(set) var dataset = Dataset.starter
    private(set) var datasetArchiveUnreadable = false
    private(set) var datasetRecoveryCopyURL: URL?
    var selectedWord: String? {
        didSet {
            guard selectedWord != oldValue else { return }
            lastTakeIssue = nil
            trainingNotice = nil
        }
    }
    var featureSet = FeatureSet(rawValue: UserDefaults.standard.object(forKey: "silentFeatureSet") as? Int
                                ?? FeatureSet.all.rawValue) {
        didSet {
            UserDefaults.standard.set(featureSet.rawValue, forKey: "silentFeatureSet")
            rebuildClassifier()
        }
    }
    private(set) var classifier: TemplateClassifier?
    private(set) var evaluation: Evaluation?
    /// Evidence for the silent templates the classifier uses, recomputed whenever they change, so Silent Use
    /// unlocks again after a relaunch without a trip to Evaluate.
    private(set) var silentEvidence: Evaluation?
    private(set) var isCheckingSilentEvidence = false
    /// Why the latest capture was not saved (Train) or not trusted (Silent Use).
    private(set) var lastTakeIssue: TakeIssue?
    /// A short note on Train: a word finished and the next one picked, a new session, removed takes.
    private(set) var trainingNotice: String?
    /// The latest silent capture's outcome. Each one has a new id, so the HUD can show it again.
    private(set) var silentFeedback: SilentCaptureFeedback?
    private(set) var isEvaluating = false
    private(set) var lastTemplateID: Template.ID?
    var trainingCondition: SessionRecorder.Condition = .silent {
        didSet {
            evaluation = nil
            syncCaptureMode()
        }
    }
    private(set) var experimentSessionID = UUID()
    var dataMessage: String?
    private(set) var dictationHistoryMessage: String?
    private(set) var dictationHistoryRecoveryCopyURL: URL?
    private(set) var dictationHistoryArchiveUnreadable = false
    private(set) var fileTranscriptionSessions: [FileTranscriptionSession]
    private(set) var fileTranscriptionHistoryMessage: String?
    private(set) var fileTranscriptionHistoryRecoveryCopyURL: URL?
    private(set) var fileTranscriptionHistoryArchiveUnreadable = false
    private(set) var pendingPersonalDataBackup: HushKeyPersonalDataBackup?

    var captureShortcut: CaptureShortcut = CaptureShortcut(
        rawValue: UserDefaults.standard.string(forKey: CaptureShortcut.preferenceKey) ?? "") ?? .default {
        didSet { UserDefaults.standard.set(captureShortcut.rawValue, forKey: CaptureShortcut.preferenceKey) }
    }

    var dictationShortcut: DictationShortcut = DictationShortcut(
        rawValue: UserDefaults.standard.string(forKey: DictationShortcut.preferenceKey) ?? "") ?? .default {
        didSet {
            UserDefaults.standard.set(dictationShortcut.rawValue, forKey: DictationShortcut.preferenceKey)
            if started, !shortcutsSuspended { installDictationShortcut() }
        }
    }
    var selectedTextEditShortcut: SelectedTextEditShortcut = SelectedTextEditShortcut(
        rawValue: UserDefaults.standard.string(forKey: SelectedTextEditShortcut.preferenceKey) ?? "") ?? .default {
        didSet {
            UserDefaults.standard.set(selectedTextEditShortcut.rawValue, forKey: SelectedTextEditShortcut.preferenceKey)
            if started, !shortcutsSuspended { installSelectedTextEditShortcut() }
        }
    }
    var dictationCaptureBehavior: DictationCaptureBehavior = DictationCaptureBehavior(
        rawValue: UserDefaults.standard.string(forKey: DictationCaptureBehavior.preferenceKey) ?? "") ?? .hold {
        didSet {
            UserDefaults.standard.set(dictationCaptureBehavior.rawValue, forKey: DictationCaptureBehavior.preferenceKey)
            if started, !shortcutsSuspended { installDictationShortcut() }
        }
    }
    /// Pastes the last transcript from any app; nil when turned off.
    var pasteLastShortcut: PasteLastShortcut? = {
        let raw = UserDefaults.standard.string(forKey: PasteLastShortcut.preferenceKey)
        if raw == PasteLastShortcut.offValue { return nil }
        return raw.flatMap(PasteLastShortcut.init(rawValue:)) ?? .default
    }() {
        didSet {
            UserDefaults.standard.set(pasteLastShortcut?.rawValue ?? PasteLastShortcut.offValue,
                                      forKey: PasteLastShortcut.preferenceKey)
            if started, !shortcutsSuspended { installPasteLastShortcut() }
        }
    }
    private(set) var pasteLastShortcutStatus = "Shortcut is not registered yet."
    /// What each action is set to, for the recorder's conflict check.
    var shortcutAssignments: [ShortcutAction: KeyCombo] {
        var assignments: [ShortcutAction: KeyCombo] = [
            .dictation: dictationShortcut.combo,
            .editSelection: selectedTextEditShortcut.combo,
            .insertAgain: insertion.shortcut.combo,
            .undoInsertion: TextInsertionService.undoShortcut,
            .silentCapture: captureShortcut.combo,
        ]
        assignments[.pasteLast] = pasteLastShortcut?.combo
        return assignments
    }
    private(set) var dictationShortcutStatus = "Shortcut is not registered yet."
    var dictationShortcutNeedsAttention: Bool {
        dictationShortcutStatus.hasPrefix("Could not") || dictationShortcutStatus.hasPrefix("Set ")
    }
    private(set) var selectedTextEditShortcutStatus = "Shortcut is not registered yet."
    var dictationTerms = UserDefaults.standard.string(forKey: "dictationTerms") ?? "" {
        didSet { UserDefaults.standard.set(dictationTerms, forKey: "dictationTerms") }
    }
    var dictationSnippets = UserDefaults.standard.string(forKey: "dictationSnippets") ?? "" {
        didSet { UserDefaults.standard.set(dictationSnippets, forKey: "dictationSnippets") }
    }
    var dictationCorrectionRules = UserDefaults.standard.string(forKey: "dictationCorrectionRules") ?? "" {
        didSet { UserDefaults.standard.set(dictationCorrectionRules, forKey: "dictationCorrectionRules") }
    }
    var writingStylePresets = WritingStylePresetStore.load()
    var dictationLanguage = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "en-US" {
        didSet { UserDefaults.standard.set(dictationLanguage, forKey: "dictationLanguage") }
    }
    var dictationEngine = DictationEngine(rawValue: UserDefaults.standard.string(forKey: DictationEngine.storageKey) ?? "")
        ?? .appleSpeech {
        didSet {
            UserDefaults.standard.set(dictationEngine.rawValue, forKey: DictationEngine.storageKey)
            if dictationEngine == .parakeet, parakeet.isDownloaded { parakeet.warmUp() }
        }
    }
    var dictationMode = DictationMode(rawValue: UserDefaults.standard.string(forKey: "dictationMode") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(dictationMode.rawValue, forKey: "dictationMode") }
    }
    var dictationAppProfiles: [DictationAppProfile] = {
        guard let data = UserDefaults.standard.data(forKey: "dictationAppProfiles"),
              let profiles = try? JSONDecoder().decode([DictationAppProfile].self, from: data) else { return [] }
        return profiles
    }() {
        didSet {
            guard let data = try? JSONEncoder().encode(dictationAppProfiles) else { return }
            UserDefaults.standard.set(data, forKey: "dictationAppProfiles")
        }
    }
    var usesNearbyTextHints = UserDefaults.standard.object(forKey: "useNearbyTextHints") as? Bool ?? false {
        didSet { UserDefaults.standard.set(usesNearbyTextHints, forKey: "useNearbyTextHints") }
    }
    /// Types each settled phrase while you speak, in fields HushKey can read back. Off by default.
    var typesWhileSpeaking = UserDefaults.standard.bool(forKey: "typesWhileSpeaking") {
        didSet { UserDefaults.standard.set(typesWhileSpeaking, forKey: "typesWhileSpeaking") }
    }
    var appliesSpokenCorrections = UserDefaults.standard.object(forKey: "applySpokenCorrections") as? Bool ?? true {
        didSet { UserDefaults.standard.set(appliesSpokenCorrections, forKey: "applySpokenCorrections") }
    }
    /// Drops um, uh, stutters and comma-set tics. On by default, under a new key so the old
    /// off-by-default setting doesn't keep it off.
    var cleansDictationFillers = UserDefaults.standard.object(forKey: "removeFillerWords") as? Bool ?? true {
        didSet { UserDefaults.standard.set(cleansDictationFillers, forKey: "removeFillerWords") }
    }
    /// After the rules, Apple Intelligence on this Mac drops the fillers they can't judge and
    /// fixes punctuation. It can only delete fillers, never reword.
    var polishesWithAppleIntelligence = UserDefaults.standard.object(forKey: "smartCleanup") as? Bool ?? false {
        didSet { UserDefaults.standard.set(polishesWithAppleIntelligence, forKey: "smartCleanup") }
    }
    @ObservationIgnored private var smartCleanupSession: AnyObject?
    private var usesSmartCleanup: Bool {
        activeDictationUsesSmartCleanup
    }
    var showsFloatingPill = UserDefaults.standard.object(forKey: "showFloatingPill") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsFloatingPill, forKey: "showFloatingPill")
            // Turned on or off by hand: that choice wins over a pending "Hide for 1 hour".
            if !isApplyingTemporaryPillHide, pillHiddenUntil != nil {
                pillUnhideTask?.cancel()
                pillUnhideTask = nil
                pillHiddenUntil = nil
            }
        }
    }
    @ObservationIgnored private var isApplyingTemporaryPillHide = false
    @ObservationIgnored private var pillUnhideTask: Task<Void, Never>?
    private(set) var pillHiddenUntil: Date?

    /// Hides the floating pill temporarily, then brings it back after `duration` (e.g. 1 hour).
    func hideFloatingPill(for duration: TimeInterval) {
        pillUnhideTask?.cancel()
        let until = Date().addingTimeInterval(duration)
        isApplyingTemporaryPillHide = true
        showsFloatingPill = false
        isApplyingTemporaryPillHide = false
        pillHiddenUntil = until
        pillUnhideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled, self.pillHiddenUntil == until else { return }
            self.isApplyingTemporaryPillHide = true
            self.showsFloatingPill = true
            self.isApplyingTemporaryPillHide = false
            self.pillHiddenUntil = nil
        }
    }

    /// Brings the floating pill back immediately, cancelling any temporary hide timer.
    func unhideFloatingPill() {
        pillUnhideTask?.cancel()
        pillUnhideTask = nil
        pillHiddenUntil = nil
        showsFloatingPill = true
    }
    /// Tone per context (Personal messages, Work messages, Email, Other); see the Style page.
    var dictationToneSettings = AppModel.loadToneSettings() {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: dictationToneSettings.tones.map { ($0.key.rawValue, $0.value.rawValue) })
            UserDefaults.standard.set(stored, forKey: "dictationTones")
        }
    }
    /// Soft cues instead of on-screen confirmations: the mic opened, the words landed, or the
    /// dictation needs attention. On by default (a new key, so the old off-by-default start/stop
    /// setting doesn't silence them).
    var playsDictationSounds = UserDefaults.standard.object(forKey: "playDictationCues") as? Bool ?? true {
        didSet { UserDefaults.standard.set(playsDictationSounds, forKey: "playDictationCues") }
    }
    @ObservationIgnored private let cuePlayer = DictationSoundPlayer()
    /// Silences music and videos while the mic is open, then brings them back (Wispr Flow's
    /// "mute music while dictating"). On by default.
    var mutesAudioWhileDictating = UserDefaults.standard.object(forKey: "muteAudioWhileDictating") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(mutesAudioWhileDictating, forKey: "muteAudioWhileDictating")
            if !mutesAudioWhileDictating { outputMuter.restore() }
        }
    }
    @ObservationIgnored private let outputMuter = OutputMuter()
    /// On keeps a Dock icon at all times. Off (the default, like TypeWhisper and Wispr Flow) makes
    /// HushKey a menu bar app that only shows in the Dock and ⌘-Tab while its window is open.
    var showsInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(showsInDock, forKey: "showInDock")
            applyDockVisibility()
        }
    }
    /// Mirrors the login item macOS has on record, so a change in System Settings shows here.
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginMessage: String?
    var savesDictationHistory = UserDefaults.standard.object(forKey: "saveDictationHistory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(savesDictationHistory, forKey: "saveDictationHistory") }
    }
    /// How long saved transcripts stay before HushKey deletes them from this Mac.
    var dictationHistoryRetention = DictationHistoryRetention(
        rawValue: UserDefaults.standard.string(forKey: DictationHistoryRetention.preferenceKey) ?? "") ?? .default {
        didSet {
            UserDefaults.standard.set(dictationHistoryRetention.rawValue, forKey: DictationHistoryRetention.preferenceKey)
            pruneDictationHistory()
        }
    }
    private(set) var dictationHistory: [DictationHistoryEntry]
    private(set) var didInsertCurrentDictation = false {
        didSet {
            // Name the app the words went into, for the pill's "Typed into …" confirmation.
            guard didInsertCurrentDictation != oldValue else { return }
            typedIntoAppName = didInsertCurrentDictation
                ? (dictationTargetApp?.localizedName ?? capturedInsertionTargetName) : nil
        }
    }
    /// The app the current dictation was typed into, once it has been.
    private(set) var typedIntoAppName: String?
    private(set) var didCompleteFirstDictation = UserDefaults.standard.bool(forKey: "completedFirstDictation")
    private(set) var rawDictationText = ""
    private(set) var transformUndoOriginalText: String?
    private(set) var transformUndoOutputText: String?
    var canUndoLocalTransform: Bool {
        guard let output = transformUndoOutputText else { return false }
        return !didInsertCurrentDictation && !audio.isRunning && !isFinalizingDictation && transcriber.text == output
    }
    private(set) var activeDictationMode: DictationMode = .natural
    private(set) var activeDictationProfileName: String?
    private(set) var activeDictationWritingStylePresetID: UUID?
    private(set) var activeDictationTarget: String?
    private(set) var capturedInsertionTargetName: String?
    private(set) var isInsertingDictation = false
    private(set) var selectedTextEditTargetName: String?
    private(set) var selectedTextEditOriginal = ""
    private(set) var selectedTextEditInstruction = ""
    private(set) var selectedTextEditDraft = ""
    private(set) var selectedTextEditStatus: String?
    var selectedTextEditLiveInstruction: String { selectedEditTranscriber.text }
    private(set) var isStartingSelectedTextEdit = false
    private(set) var isStartingDictation = false
    /// Finish was pressed while the microphone was open but recognition was still starting.
    @ObservationIgnored private var stopsWhenStarted = false
    private(set) var isSelectedTextEditCapturing = false
    private(set) var isFinalizingSelectedTextEdit = false
    private(set) var isGeneratingSelectedTextEdit = false
    private(set) var isApplyingSelectedTextEdit = false
    private(set) var selectedTextEditApplied = false
    private(set) var usedNearbyTextHints = false
    private(set) var isFinalizingDictation = false
    /// The pill's error state for the last dictation, with the recoveries it allows.
    private(set) var dictationNotice: DictationNotice? {
        didSet {
            if let dictationNotice, !dictationNotice.isNeutral, dictationNotice != oldValue { playDictationCue(.error) }
        }
    }
    /// Bumped each time a dictation ends with text, so the pill can flash its done state.
    private(set) var completedDictationCount = 0 {
        didSet {
            guard completedDictationCount > oldValue else { return }
            if dictationNotice == nil { playDictationCue(.success) }
            if !didCompleteFirstDictation {
                didCompleteFirstDictation = true
                UserDefaults.standard.set(true, forKey: "completedFirstDictation")
            }
        }
    }
    private(set) var dictationResultGeneration = 0
    /// The first-run tour is on screen (shown once on first launch; reopened from Help or Get set up).
    var showsOnboarding = false
    /// The tour's practice field is waiting for a dictation: while HushKey is in front, a finished
    /// dictation stays in the app for the field to show, instead of raising the pill's card.
    @ObservationIgnored var practiceKeepsDictationInApp = false
    /// Whether the running or last dictation has a text field to type into.
    private(set) var dictationHasTarget = false
    /// The app dictation started in, used to paste when its field refuses direct typing.
    @ObservationIgnored private var dictationTargetApp: NSRunningApplication?
    /// Keeps the finished text on the pill's card, with Copy, when there was nowhere to type it.
    private(set) var showsFinishedTranscript = false
    @ObservationIgnored private(set) var lastSavedDictationText: String?
    @ObservationIgnored private(set) var dictationStartedAt: Date?
    @ObservationIgnored private var lastDictationDuration: TimeInterval?
    /// The last cancelled recording, kept in memory for this session so History can recover it.
    /// Never written to disk; dropped on Recover, Discard, the next cancel, or quit.
    private(set) var cancelledDictation: CancelledDictation?
    @ObservationIgnored private var cancelledDictationAudio: [AVAudioPCMBuffer] = []
    @ObservationIgnored private var cancelledDictationSettings: DictationRunSettings?
    /// The History entry just deleted, for "Deleted · Undo". Memory only; the deletion is already saved.
    private(set) var deletedDictation: DeletedDictation?
    /// The latest dictation's audio, in memory only, so History can run it through the other engine.
    /// Dropped when the next dictation starts, history or session audio is deleted, or the app quits.
    @ObservationIgnored private var heldHistoryAudio: (entryID: UUID, buffers: [AVAudioPCMBuffer], engine: DictationEngine)?
    private(set) var heldHistoryAudioEntryID: UUID?
    /// Entries whose audio was held this session and has since been dropped ("Audio no longer available").
    private(set) var droppedHistoryAudioEntryIDs: Set<UUID> = []
    private(set) var retranscribingDictationID: UUID?
    @ObservationIgnored private var finishingAudioOverride: [AVAudioPCMBuffer]?
    @ObservationIgnored private var lastRecognitionUsedParakeet = false
    /// A recovered dictation is saved and shown, never typed into whatever has focus now.
    @ObservationIgnored private var finishesWithoutTyping = false
    /// The tone picked from the Style page when this dictation started.
    @ObservationIgnored private var activeDictationTone: DictationTone = .formal
    /// The input the last dictation used, for "We couldn't hear you".
    @ObservationIgnored private var lastDictationMicrophoneName: String?
    @ObservationIgnored private var cancelNoticeToken = 0
    /// Set by the app scene, so views outside it (the pill) can bring the main window back.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    var dictationStats: DictationStats { DictationStats(entries: dictationHistory) }
    var canClearDictationHistory: Bool {
        DictationHistoryClearGate.canClear(isStarting: isStartingDictation || audio.isStarting,
                                           isRecording: audio.isRunning,
                                           isFinalizing: isFinalizingDictation,
                                           transcriptionRunning: transcriber.isRunning,
                                           transcriptionFinalizing: transcriber.isFinalizing)
    }
    @ObservationIgnored private let dictationHistoryURL: URL
    /// Lifetime totals for Insights: counts by day, no text. Recorded only while history saving is on.
    private(set) var usageLedger = UsageLedger()
    @ObservationIgnored private let usageLedgerURL: URL
    @ObservationIgnored private var activeUsageCategory: UsageCategory = .other
    @ObservationIgnored private let fileTranscriptionHistoryURL: URL
    @ObservationIgnored private var fileTranscriptionSessionsDiscardedByClear = Set<UUID>()
    @ObservationIgnored private var dictationHistorySaveTask: Task<Void, Never>?
    @ObservationIgnored private var currentDictationHistoryEntryID: UUID?
    @ObservationIgnored private var capturedInsertionTarget: TextInsertionService.InsertionTarget?
    /// The current dictation's live typing, when `typesWhileSpeaking` applies to its field.
    @ObservationIgnored private var liveTyping: LiveTypingSession?
    @ObservationIgnored private var liveTypingTimer: Task<Void, Never>?
    @ObservationIgnored private let liveTypingLog = Logger(subsystem: "com.ruddvz.hushkey", category: "liveTyping")
    @ObservationIgnored private var capturedPasteTarget: TextInsertionService.PasteTarget?
    @ObservationIgnored private var selectedTextEditTarget: TextInsertionService.InsertionTarget?
    @ObservationIgnored private let selectedEditTranscriber = MicTranscriber()
    @ObservationIgnored private let retainedAudio = RetainedDictationAudio()
    @ObservationIgnored private var retainedAudioSinkID: UUID?
    @ObservationIgnored private var lastDictationContextualStrings: [String] = []
    /// This dictation is recognized by Parakeet on release; Apple Speech, if allowed, only previews it.
    @ObservationIgnored private var activeDictationUsesParakeet = false
    @ObservationIgnored private var activeDictationEngine: DictationEngine = .appleSpeech
    @ObservationIgnored private var activeParakeetNeedsReview = false
    @ObservationIgnored private var lastParakeetConfidence: Float?
    @ObservationIgnored private var lastParakeetPeakLevel: Float?
    @ObservationIgnored private let parakeetLog = Logger(subsystem: "com.ruddvz.hushkey", category: "parakeet")
    @ObservationIgnored private var activeDictationLanguageIdentifier = "en-US"
    @ObservationIgnored private var activeDictationSnippets = ""
    @ObservationIgnored private var activeDictationCorrectionRules = ""
    @ObservationIgnored private var activeDictationCleansFillers = false
    @ObservationIgnored private var activeDictationAppliesSpokenCorrections = true
    @ObservationIgnored private var activeDictationUsesSmartCleanup = false
    @ObservationIgnored private var captureDictationProfileName: String?
    @ObservationIgnored private var captureDictationWritingStylePresetID: UUID?

    // MARK: Decoding

    var useCaptureMode: CaptureController.Mode = UserDefaults.standard.string(forKey: "silentCaptureMode") == "auto"
        ? .auto : .hold {
        didSet {
            UserDefaults.standard.set(useCaptureMode == .auto ? "auto" : "hold", forKey: "silentCaptureMode")
            syncCaptureMode()
        }
    }
    var maxDistance: Double = UserDefaults.standard.object(forKey: "silentMaxDistance") as? Double ?? 1.5 {
        didSet { UserDefaults.standard.set(maxDistance, forKey: "silentMaxDistance") }
    }
    var minConfidence: Double = UserDefaults.standard.object(forKey: "silentMinConfidence") as? Double ?? 0.05 {
        didSet { UserDefaults.standard.set(minConfidence, forKey: "silentMinConfidence") }
    }
    /// Types each accepted Silent Use word into the frontmost app. Rejected matches are never typed.
    var silentTypesIntoFrontApp = UserDefaults.standard.object(forKey: "silentTypesIntoFrontApp") as? Bool ?? false {
        didSet { UserDefaults.standard.set(silentTypesIntoFrontApp, forKey: "silentTypesIntoFrontApp") }
    }
    private(set) var decoded: [DecodedWord] = []
    private(set) var lastSegment: [MotionSample] = []
    private(set) var lastInsertedPredictionID: UUID?

    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private let dictationHotKey = GlobalHotKeyRegistration(id: 2)
    @ObservationIgnored private let functionKey = FunctionKeyMonitor()
    @ObservationIgnored private var functionKeyInstalledTrusted = false
    @ObservationIgnored private let selectedTextEditHotKey = GlobalHotKeyRegistration(id: 4)
    @ObservationIgnored private let pasteLastHotKey = GlobalHotKeyRegistration(id: 5)
    @ObservationIgnored private let dictationMouseButton = MouseButtonMonitor()
    @ObservationIgnored private let pasteLastMouseButton = MouseButtonMonitor()
    /// True while Settings records a new shortcut, so pressing a current one doesn't fire it.
    @ObservationIgnored private var shortcutsSuspended = false
    /// Hold Control on its own to capture a silent word, the way fn holds dictation. Works in other apps.
    @ObservationIgnored private let silentControlKey = FunctionKeyMonitor(key: .control)
    @ObservationIgnored private var silentControlKeyInstalledTrusted = false
    @ObservationIgnored private var silentEvidenceTask: Task<Void, Never>?
    @ObservationIgnored private var takeIssueCache: [Template.ID: TakeIssue?] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var motionStarted = false
    /// The dictation key is held down (hold to talk). Observed so the pill can drop its buttons.
    private(set) var dictationShortcutHeld = false
    @ObservationIgnored private var selectedTextEditShortcutHeld = false
    @ObservationIgnored private var dictationStartGeneration = 0
    @ObservationIgnored private var selectedTextEditGeneration = 0

    init(dictationHistoryURL: URL = DictationHistoryStore.url,
         fileTranscriptionHistoryURL: URL = FileTranscriptionSessionStore.url,
         sessionRecorder: SessionRecorder? = nil) {
        self.dictationHistoryURL = dictationHistoryURL
        recorder = sessionRecorder ?? SessionRecorder()
        switch TemplateStore.loadState() {
        case .missing:
            dataset = .starter
        case .loaded(let savedDataset):
            dataset = savedDataset
        case .unreadable(let recoveryCopyURL):
            dataset = .starter
            datasetArchiveUnreadable = true
            datasetRecoveryCopyURL = recoveryCopyURL
            dataMessage = Self.archiveRecoveryMessage("Silent Lab dataset", copy: recoveryCopyURL)
        }
        var loadedHistory: [DictationHistoryEntry] = []
        switch DictationHistoryStore.loadState(from: dictationHistoryURL) {
        case .missing:
            dictationHistory = []
        case .loaded(let entries):
            dictationHistory = entries
            loadedHistory = entries
        case .unreadable(let recoveryCopyURL):
            dictationHistory = []
            dictationHistoryRecoveryCopyURL = recoveryCopyURL
            dictationHistoryArchiveUnreadable = true
            dictationHistoryMessage = Self.archiveRecoveryMessage("Dictation history", copy: recoveryCopyURL)
        }
        let usageLedgerURL = dictationHistoryURL.deletingLastPathComponent().appending(path: "usage.json")
        self.usageLedgerURL = usageLedgerURL
        usageLedger = UsageLedgerStore.load(from: usageLedgerURL) ?? UsageLedger.seeded(from: loadedHistory)
        self.fileTranscriptionHistoryURL = fileTranscriptionHistoryURL
        switch FileTranscriptionSessionStore.loadState(from: fileTranscriptionHistoryURL) {
        case .missing:
            fileTranscriptionSessions = []
        case .loaded(let sessions):
            fileTranscriptionSessions = sessions
        case .unreadable(let recoveryCopyURL):
            fileTranscriptionSessions = []
            fileTranscriptionHistoryRecoveryCopyURL = recoveryCopyURL
            fileTranscriptionHistoryArchiveUnreadable = true
            fileTranscriptionHistoryMessage = Self.archiveRecoveryMessage("File transcript history", copy: recoveryCopyURL)
        }
        let captureGate = AudioCaptureGate()
        self.captureGate = captureGate
        meetingNotes = MeetingNotesService(captureGate: captureGate)
        selectedWord = dataset.vocabulary.first
        fileTranscriber.onSessionUpdate = { [weak self] session in
            self?.saveFileTranscriptionSession(session)
        }
        whisperFileTranscriber.onSessionUpdate = { [weak self] session in
            self?.saveFileTranscriptionSession(session)
        }
        insertion.onInsertShortcut = { [weak self] in self?.insertLatestOutput() }
        insertion.onUndoShortcut = { [weak self] in self?.undoLastInsertion() }
        rebuildClassifier()
        // Load Parakeet now, so the first dictation doesn't wait for the Neural Engine.
        if dictationEngine == .parakeet, parakeet.isDownloaded, !AppDataDirectory.isRunningTests { parakeet.warmUp() }
    }

    @discardableResult
    func saveFileTranscriptionSession(_ session: FileTranscriptionSession) -> Bool {
        guard !fileTranscriptionSessionsDiscardedByClear.contains(session.id) else { return true }
        let updated = FileTranscriptionSessionStore.upserting(session, into: fileTranscriptionSessions)
        do {
            try FileTranscriptionSessionStore.save(updated, to: fileTranscriptionHistoryURL)
            fileTranscriptionSessions = updated
            if fileTranscriptionHistoryRecoveryCopyURL == nil { fileTranscriptionHistoryMessage = nil }
            return true
        } catch {
            fileTranscriptionHistoryMessage = "Couldn’t save this transcript locally: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteFileTranscriptionSession(_ session: FileTranscriptionSession) -> Bool {
        let updated = FileTranscriptionSessionStore.deleting(id: session.id, from: fileTranscriptionSessions)
        do {
            try FileTranscriptionSessionStore.save(updated, to: fileTranscriptionHistoryURL)
            fileTranscriptionSessions = updated
            if fileTranscriptionHistoryRecoveryCopyURL == nil { fileTranscriptionHistoryMessage = nil }
            return true
        } catch {
            fileTranscriptionHistoryMessage = "Couldn’t delete this transcript: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func clearFileTranscriptionHistory() -> Bool {
        let activeSessionIDs = Set([
            fileTranscriber.isTranscribing ? fileTranscriber.activeSessionID : nil,
            whisperFileTranscriber.isTranscribing ? whisperFileTranscriber.activeSessionID : nil
        ].compactMap { $0 })
        return clearFileTranscriptionHistory(discardingActiveSessionIDs: activeSessionIDs)
    }

    @discardableResult
    func clearFileTranscriptionHistory(discardingActiveSessionIDs activeSessionIDs: Set<UUID>) -> Bool {
        let recoveryCopyURL = fileTranscriptionHistoryRecoveryCopyURL
        do {
            try FileTranscriptionSessionStore.deleteAll(at: fileTranscriptionHistoryURL)
            fileTranscriptionSessionsDiscardedByClear.formUnion(activeSessionIDs)
            fileTranscriptionSessions.removeAll()
            fileTranscriptionHistoryRecoveryCopyURL = nil
            fileTranscriptionHistoryArchiveUnreadable = false
            let recoveryNotice = recoveryCopyURL.map { " Recovery copy: \($0.path)" } ?? ""
            fileTranscriptionHistoryMessage = (activeSessionIDs.isEmpty
                ? "Saved file transcript history was deleted from this Mac."
                : "Saved history was deleted. The in-progress transcript can still be exported, but it will not be added back to history.") + recoveryNotice
            return true
        } catch {
            fileTranscriptionHistoryMessage = "Couldn’t delete saved transcripts: \(error.localizedDescription)"
            return false
        }
    }

    func start() {
        guard !started else { return }
        started = true
        motion.onSample = { [weak self] sample in self?.ingest(sample) }
        motion.onStatusChange = { [weak self] status in
            if status != .streaming { self?.capture.cancel() }
        }
        capture.onSegment = { [weak self] segment in self?.handleSegment(segment) }
        capture.onTooShort = { [weak self] in self?.handleTooShortCapture() }
        transcriber.onTextChange = { [weak self] text in self?.liveTranscriptChanged(text) }
        #if LIVE_TYPING_REHEARSAL
        rehearseLiveTypingIfRequested()
        #endif
        audio.refreshDevices()
        installKeyMonitor()
        installDictationShortcut()
        installSelectedTextEditShortcut()
        installPasteLastShortcut()
        insertion.restore()
        pruneDictationHistory()
        updateMotionActivity()
        syncCaptureMode()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFunctionKeyStatus()
                self?.syncSilentControlKey()
                self?.insertion.restore()
                self?.refreshLaunchAtLogin()
                self?.pruneDictationHistory()
            }
        }
    }

    private func ingest(_ sample: MotionSample) {
        capture.ingest(sample)
        recorder.record(sample)
    }

    private func syncCaptureMode() {
        capture.autoEnabled = isMotionInferenceEnabled && screen == .use && useCaptureMode == .auto
        syncSilentControlKey()
    }

    /// Control works as the silent hold key only on Train and Silent Use, so it never interferes elsewhere.
    private func syncSilentControlKey() {
        let wanted = started && [.train, .use].contains(screen)
        let trusted = AXIsProcessTrusted()
        if wanted, !silentControlKey.isInstalled || (trusted && !silentControlKeyInstalledTrusted) {
            // Monitors added before Accessibility access was granted stay deaf, so add them again.
            silentControlKey.uninstall()
            silentControlKey.onAction = { [weak self] action in self?.handleSilentControlKey(action) }
            silentControlKey.install()
            silentControlKeyInstalledTrusted = trusted
        } else if !wanted, silentControlKey.isInstalled {
            silentControlKey.uninstall()
        }
    }

    /// Whether holding Control should capture right now: a selected word on Train, or an unlocked
    /// Silent Use in hold mode.
    var silentControlKeyCaptures: Bool {
        switch screen {
        case .train: selectedWord != nil
        case .use: useCaptureMode == .hold && isMotionInferenceEnabled && classifier != nil
        default: false
        }
    }

    private func handleSilentControlKey(_ action: FunctionKeyGesture.Action) {
        switch action {
        case .startHold:
            guard silentControlKeyCaptures, motion.status == .streaming, captureGate.owner == nil else { return }
            capture.begin()
        case .endHold:
            capture.end()
        case .abortHold:
            capture.cancel() // Control was part of a shortcut such as ⌃C
        case .startHandsFree, .stopHandsFree:
            silentControlKey.reset() // the Control monitor never offers hands-free; keep it that way
        case .none, .scheduleHoldStart, .cancelHoldStart:
            break
        }
    }

    private func updateMotionActivity() {
        guard started else { return }
        let needsMotion = [.setup, .train, .evaluate, .use].contains(screen)
        if needsMotion && !motionStarted {
            motionStarted = true
            motion.start()
        } else if !needsMotion && motionStarted {
            motion.stop()
            motionStarted = false
        }
    }

    private func handleSegment(_ segment: [MotionSample]) {
        lastSegment = segment
        switch screen {
        case .train:
            if let word = selectedWord {
                if let issue = MotionFeatures.takeIssue(segment) {
                    lastTakeIssue = issue
                    silentFeedback = SilentCaptureFeedback(kind: .problem, text: issue.shortMessage)
                    recorder.logEvent(segment, kind: "train-rejected", label: word, confidence: nil)
                    return
                }
                lastTakeIssue = nil
                trainingNotice = nil
                let saved = addTemplate(Template(label: word, samples: segment,
                                                 condition: trainingCondition, sessionID: experimentSessionID))
                recorder.logEvent(segment, kind: "train", label: word, confidence: nil)
                let count = templateCount(for: word, condition: trainingCondition)
                silentFeedback = SilentCaptureFeedback(
                    kind: saved ? .saved : .problem,
                    text: saved ? "Saved “\(word)” · \(min(count, Self.takesPerWord))/\(Self.takesPerWord)"
                        : "Couldn’t save “\(word)” to this Mac")
                if count == Self.takesPerWord { advanceTraining(from: word) }
            } else if recorder.isRecording {
                recorder.logEvent(segment, kind: "segment", label: recorder.prompt, confidence: nil)
            }
        case .use:
            guard isMotionInferenceEnabled, let classifier else {
                recorder.logEvent(segment, kind: "blocked-no-evidence", label: "", confidence: nil)
                return
            }
            var prediction = classifier.predict(segment, maxDistance: maxDistance, minConfidence: minConfidence)
            lastTakeIssue = MotionFeatures.takeIssue(segment)
            if lastTakeIssue != nil { prediction.accepted = false }
            lastInsertedPredictionID = nil
            let word = DecodedWord(prediction: prediction)
            decoded.append(word)
            recorder.logEvent(segment, kind: prediction.accepted ? "decode" : "reject",
                              label: prediction.best?.label ?? "", confidence: prediction.confidence)
            if let issue = lastTakeIssue {
                silentFeedback = SilentCaptureFeedback(kind: .problem, text: issue.shortMessage)
            } else if prediction.best?.label == TemplateClassifier.restLabel {
                silentFeedback = SilentCaptureFeedback(kind: .ignored, text: "Nothing to type")
            } else if !prediction.accepted {
                silentFeedback = SilentCaptureFeedback(kind: .unsure, text: "Not sure · nothing typed")
            } else if typeSilentWordIfAllowed(word) {
                silentFeedback = SilentCaptureFeedback(kind: .typed, text: word.text)
            } else {
                silentFeedback = SilentCaptureFeedback(kind: .notTyped, text: "“\(word.text)” · not typed")
            }
        case .settings:
            recorder.logEvent(segment, kind: "segment", label: recorder.prompt, confidence: nil)
        case .dictation, .transforms, .files, .meetings, .setup, .evaluate, .personalization, .style, .insights:
            if recorder.isRecording {
                recorder.logEvent(segment, kind: "segment", label: recorder.prompt, confidence: nil)
            }
        }
    }

    // MARK: App-local hold shortcut

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            let isDown = event.type == .keyDown
            let isRepeat = isDown && event.isARepeat
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard event.keyCode == self.captureShortcut.keyCode,
                      self.shortcutCapturesMotion,
                      NSApp.isActive,
                      event.modifierFlags.intersection([.command, .option, .control, .shift]) == self.captureShortcut.modifiers else { return false }
                if !isDown {
                    self.capture.end()
                } else if !isRepeat {
                    self.capture.begin()
                }
                return true
            }
            return consumed ? nil : event
        }
    }

    private var shortcutCapturesMotion: Bool {
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        if recorder.isRecording { return true }
        switch screen {
        case .train: return selectedWord != nil && motion.status == .streaming
        case .use: return useCaptureMode == .hold && isMotionInferenceEnabled && classifier != nil
        case .dictation: return false
        case .transforms: return false
        case .files: return false
        case .meetings: return false
        case .personalization: return false
        case .style: return false
        case .insights: return false
        case .settings: return false
        case .setup, .evaluate: return false
        }
    }

    // MARK: Dataset editing

    func templates(for word: String, condition: SessionRecorder.Condition? = nil) -> [Template] {
        dataset.templates.filter {
            $0.label == word && (condition == nil || ($0.condition ?? .silent) == condition)
        }
    }

    /// Takes that count: in this condition and free of head movement or a bad length.
    func templateCount(for word: String, condition: SessionRecorder.Condition) -> Int {
        templates(for: word, condition: condition).filter { takeIssue(of: $0) == nil }.count
    }

    /// Why a saved take is unusable, under today's checks. Takes never change, so this is cached.
    func takeIssue(of template: Template) -> TakeIssue? {
        if let cached = takeIssueCache[template.id] { return cached }
        let issue = MotionFeatures.takeIssue(template.samples)
        takeIssueCache[template.id] = .some(issue)
        return issue
    }

    /// Every take the classifier and the evidence checks may use in this condition. Takes where the
    /// head moved stay on screen, flagged, but never teach the classifier.
    func usableTemplates(condition: SessionRecorder.Condition) -> [Template] {
        dataset.templates.filter { ($0.condition ?? .silent) == condition && takeIssue(of: $0) == nil }
    }

    func beginNewExperimentSession() {
        experimentSessionID = UUID()
        lastTakeIssue = nil
        trainingNotice = "New session. Record every word \(Self.sessionTakesPerWord) or more times so it can be tested against the others."
    }

    // MARK: Training protocol

    nonisolated static let takesPerWord = 10
    nonisolated static let minimumWords = 5
    /// Takes of every word a session needs before it can stand as a held-out test.
    nonisolated static let sessionTakesPerWord = 3

    /// 5 or more words with 10 takes each in this condition: what Evaluate needs.
    func meetsTemplateProtocol(condition: SessionRecorder.Condition) -> Bool {
        dataset.vocabulary.count >= Self.minimumWords &&
            dataset.vocabulary.allSatisfy { templateCount(for: $0, condition: condition) >= Self.takesPerWord }
    }

    /// Words still short of 10 takes in this condition, with how many each needs, in list order.
    func takesStillNeeded(condition: SessionRecorder.Condition) -> [(word: String, needed: Int)] {
        dataset.vocabulary.compactMap { word in
            let needed = Self.takesPerWord - templateCount(for: word, condition: condition)
            return needed > 0 ? (word, needed) : nil
        }
    }

    /// Sessions that hold every word often enough to be held out against the others.
    func completeSessionCount(condition: SessionRecorder.Condition) -> Int {
        Self.completeSessionCount(templates: usableTemplates(condition: condition), vocabulary: dataset.vocabulary,
                                  condition: condition)
    }

    nonisolated static func completeSessionCount(templates: [Template], vocabulary: [String],
                                                 condition: SessionRecorder.Condition) -> Int {
        guard !vocabulary.isEmpty else { return 0 }
        let sessions = Dictionary(grouping: templates.filter { ($0.condition ?? .silent) == condition && $0.sessionID != nil },
                                  by: { $0.sessionID ?? UUID() })
        return sessions.values.filter { takes in
            let counts = Dictionary(grouping: takes, by: \.label).mapValues(\.count)
            return vocabulary.allSatisfy { counts[$0, default: 0] >= sessionTakesPerWord }
        }.count
    }

    /// Takes recorded in the current session, in this condition.
    func currentSessionTakeCount(condition: SessionRecorder.Condition) -> Int {
        usableTemplates(condition: condition).filter { $0.sessionID == experimentSessionID }.count
    }

    /// Takes saved before the length and head-movement checks existed that would fail them now.
    func flaggedTakes(for word: String, condition: SessionRecorder.Condition) -> [Template] {
        templates(for: word, condition: condition).filter { takeIssue(of: $0) != nil }
    }

    func removeFlaggedTakes(for word: String, condition: SessionRecorder.Condition) {
        let ids = Set(flaggedTakes(for: word, condition: condition).map(\.id))
        guard !ids.isEmpty else { return }
        dataset.templates.removeAll { ids.contains($0.id) }
        persist()
        trainingNotice = "Removed \(ids.count) flagged \(ids.count == 1 ? "take" : "takes") of “\(word)”."
    }

    /// A word just reached 10 takes: move to the next one that still needs takes.
    private func advanceTraining(from word: String) {
        let words = dataset.vocabulary
        guard let index = words.firstIndex(of: word) else { return }
        let order = words[(index + 1)...] + words[..<index]
        if let next = order.first(where: { templateCount(for: $0, condition: trainingCondition) < Self.takesPerWord }) {
            selectedWord = next
            trainingNotice = "“\(word)” has \(Self.takesPerWord) takes. Next: “\(next)”."
        } else if dataset.vocabulary.count >= Self.minimumWords {
            trainingNotice = "Every word has \(Self.takesPerWord) takes. Evaluate next, or record a new session."
        } else {
            trainingNotice = "“\(word)” has \(Self.takesPerWord) takes. Add \(Self.minimumWords - words.count) more \(Self.minimumWords - words.count == 1 ? "word" : "words")."
        }
    }

    private func handleTooShortCapture() {
        guard [.train, .use].contains(screen) else { return }
        lastTakeIssue = .tooShort
        silentFeedback = SilentCaptureFeedback(kind: .problem, text: TakeIssue.tooShort.shortMessage)
    }

    func addWord(_ raw: String) {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty, !dataset.vocabulary.contains(word) else { return }
        dataset.vocabulary.append(word)
        selectedWord = word
        persist()
    }

    func removeWord(_ word: String) {
        dataset.vocabulary.removeAll { $0 == word }
        dataset.templates.removeAll { $0.label == word }
        if selectedWord == word { selectedWord = dataset.vocabulary.first }
        persist()
    }

    @discardableResult
    func addTemplate(_ template: Template) -> Bool {
        dataset.templates.append(template)
        lastTemplateID = template.id
        return persist()
    }

    func clearTrainingData() {
        if datasetArchiveUnreadable {
            do {
                try TemplateStore.delete()
                datasetArchiveUnreadable = false
                datasetRecoveryCopyURL = nil
                dataMessage = "Unreadable dataset removed. Its recovery copy was kept if one could be made."
            } catch {
                dataMessage = "Couldn’t remove the unreadable dataset: \(error.localizedDescription)"
                return
            }
        }
        dataset.templates.removeAll()
        lastTemplateID = nil
        persist()
        if !datasetArchiveUnreadable { dataMessage = "Training templates deleted from this Mac." }
    }

    func exportDataset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "hushkey-dataset.json"
        panel.prompt = "Export Dataset"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try JSONEncoder().encode(dataset).write(to: url, options: .atomic)
            dataMessage = "Dataset exported to \(url.lastPathComponent)."
        } catch {
            dataMessage = "Dataset export failed: \(error.localizedDescription)"
        }
    }

    func exportPersonalDataBackup() {
        guard !dictationHistoryArchiveUnreadable else {
            dataMessage = "Dictation history is unreadable. Import a known-good backup or remove the damaged archive before exporting a complete personal backup."
            return
        }
        do {
            let backup = currentPersonalDataBackup()
            let data = try backup.encoded()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "HushKey-Personal-Data.json"
            panel.prompt = "Export Backup"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            dataMessage = "Personal backup exported to \(url.lastPathComponent). It contains dictation text and personalization, but no audio."
        } catch {
            dataMessage = "Personal backup export failed: \(error.localizedDescription)"
        }
    }

    /// Returns a status message, or nil when the user cancelled the panel.
    func exportVocabularyWordList() -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "HushKey-Vocabulary.txt"
        panel.prompt = "Export Words"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let terms = DictationVocabulary.terms(from: dictationTerms)
        do {
            try DictationWordList.export(terms).write(to: url, options: .atomic)
            return "Exported \(terms.count) \(terms.count == 1 ? "word" : "words") to \(url.lastPathComponent)."
        } catch {
            return "Word list export failed: \(error.localizedDescription)"
        }
    }

    /// Returns a status message, or nil when the user cancelled the panel.
    func importVocabularyWordList() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add Words"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        do {
            if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > DictationWordList.maximumFileBytes {
                throw DictationWordList.ImportError.fileTooLarge
            }
            return importVocabularyWordList(try Data(contentsOf: url))
        } catch {
            return "Word list import failed: \(error.localizedDescription)"
        }
    }

    func importVocabularyWordList(_ data: Data) -> String {
        do {
            let result = try DictationWordList.merge(data, into: DictationVocabulary.terms(from: dictationTerms))
            dictationTerms = DictationVocabulary.encode(result.terms)
            var parts = ["Added \(result.added) \(result.added == 1 ? "word" : "words")."]
            if result.duplicates > 0 { parts.append("\(result.duplicates) already in your vocabulary.") }
            if result.invalid > 0 {
                parts.append("\(result.invalid) skipped for being longer than \(DictationWordList.maximumTermLength) characters.")
            }
            return parts.joined(separator: " ")
        } catch {
            return "Word list import failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func selectPersonalDataBackup() -> Bool {
        guard captureGate.owner == nil, !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing,
              !isStartingSelectedTextEdit, !isSelectedTextEditCapturing, !isFinalizingSelectedTextEdit,
              !isGeneratingSelectedTextEdit, !isApplyingSelectedTextEdit else {
            dataMessage = "Finish the current capture before importing a backup."
            return false
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Check Backup"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        do {
            if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > HushKeyPersonalDataBackup.maximumFileBytes {
                throw HushKeyPersonalDataBackup.BackupError.fileTooLarge
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return stagePersonalDataBackup(data)
        } catch {
            pendingPersonalDataBackup = nil
            dataMessage = "Personal backup import failed: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func stagePersonalDataBackup(_ data: Data) -> Bool {
        do {
            pendingPersonalDataBackup = try HushKeyPersonalDataBackup.decode(data)
            dataMessage = "Backup checked. \(pendingPersonalDataBackup?.summary ?? "") Choose Merge or Replace to continue."
            return true
        } catch {
            pendingPersonalDataBackup = nil
            dataMessage = "Personal backup import failed: \(error.localizedDescription)"
            return false
        }
    }

    func cancelPersonalDataImport() {
        pendingPersonalDataBackup = nil
    }

    func applyPersonalDataBackup(using strategy: PersonalDataImportStrategy) {
        guard let pendingPersonalDataBackup else { return }
        guard captureGate.owner == nil, !audio.isRunning, !isFinalizingDictation,
              !transcriber.isFinalizing, !isStartingSelectedTextEdit, !isSelectedTextEditCapturing,
              !isFinalizingSelectedTextEdit, !isGeneratingSelectedTextEdit, !isApplyingSelectedTextEdit else {
            dataMessage = "Finish the current capture before importing a backup."
            return
        }

        let currentText = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentRawText = rawDictationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRawText = currentRawText.isEmpty || currentRawText == currentText ? nil : currentRawText

        if strategy == .merge, !dictationHistoryArchiveUnreadable, savesDictationHistory {
            if DictationHistorySaveGate.shouldSave(text: currentText, lastSavedText: lastSavedDictationText,
                                                  enabled: true) {
                cancelPendingDictationHistorySave()
                saveCurrentDictation()
                guard lastSavedDictationText == currentText else {
                    dataMessage = "The current dictation could not be saved first. Resolve its history save message, then import again."
                    return
                }
            }
        }

        let current = currentPersonalDataBackup()
        var resolved = pendingPersonalDataBackup.resolved(against: current, using: strategy)
        var preservedActiveEntryID: UUID?
        if strategy == .replace, savesDictationHistory, !currentText.isEmpty {
            if let matchingEntry = resolved.dictationHistory.first(where: {
                $0.text == currentText && $0.rawText == normalizedRawText
            }) {
                preservedActiveEntryID = matchingEntry.id
            } else {
                guard resolved.dictationHistory.count < HushKeyPersonalDataBackup.maximumHistoryEntries else {
                    dataMessage = "This backup already has 50 dictations. Save or clear the open transcript before replacing history, then import again."
                    return
                }
                let previousEntry = currentDictationHistoryEntryID.flatMap { id in
                    dictationHistory.first { $0.id == id }
                }
                let candidateID = currentDictationHistoryEntryID.flatMap { id in
                    resolved.dictationHistory.contains { $0.id == id } ? nil : id
                } ?? UUID()
                let entry = DictationHistoryEntry(id: candidateID,
                                                  createdAt: previousEntry?.createdAt ?? Date(),
                                                  text: currentText,
                                                  rawText: normalizedRawText,
                                                  duration: lastDictationDuration ?? previousEntry?.duration)
                resolved.dictationHistory.insert(entry, at: 0)
                preservedActiveEntryID = entry.id
            }
        }
        do {
            try resolved.validate()
            let previousStyles = writingStylePresets
            try saveWritingStylePresets(resolved.writingStyles)
            do {
                if dictationHistoryArchiveUnreadable {
                    try DictationHistoryStore.replaceAfterExplicitImport(resolved.dictationHistory, to: dictationHistoryURL)
                } else {
                    try DictationHistoryStore.save(resolved.dictationHistory, to: dictationHistoryURL)
                }
            } catch {
                try? saveWritingStylePresets(previousStyles)
                throw error
            }
            dictationHistory = resolved.dictationHistory
            dictationHistoryRecoveryCopyURL = nil
            dictationHistoryArchiveUnreadable = false
            dictationHistoryMessage = nil
            dictationTerms = DictationVocabulary.encode(resolved.vocabulary)
            dictationSnippets = resolved.snippets
            dictationCorrectionRules = resolved.correctionRules
            dictationAppProfiles = resolved.appProfiles
            let validStyleIDs = Set(resolved.writingStyles.map(\.id))
            if let activeStyleID = activeDictationWritingStylePresetID, !validStyleIDs.contains(activeStyleID) {
                activeDictationWritingStylePresetID = nil
            }
            let activeEntry = preservedActiveEntryID.flatMap { id in
                resolved.dictationHistory.first { $0.id == id && $0.text == currentText }
            } ?? resolved.dictationHistory.first(where: {
                !currentText.isEmpty && $0.text == currentText && $0.rawText == normalizedRawText
            })
            currentDictationHistoryEntryID = activeEntry?.id
            lastSavedDictationText = activeEntry?.text
            self.pendingPersonalDataBackup = nil
            let transcriptNote: String
            if !currentText.isEmpty, activeEntry != nil, strategy == .replace {
                transcriptNote = " The open transcript was kept in history."
            } else if !currentText.isEmpty, activeEntry == nil {
                transcriptNote = " The open transcript remains in the editor; transcript history is off, so it is not saved."
            } else {
                transcriptNote = ""
            }
            dataMessage = "Personal backup \(strategy == .merge ? "merged" : "restored"): \(resolved.summary).\(transcriptNote) Audio is not included."
        } catch {
            dataMessage = "Personal backup could not be applied: \(error.localizedDescription)"
        }
    }

    private func currentPersonalDataBackup() -> HushKeyPersonalDataBackup {
        HushKeyPersonalDataBackup(
            dictationHistory: dictationHistory,
            vocabulary: DictationVocabulary.terms(from: dictationTerms),
            snippets: dictationSnippets,
            correctionRules: dictationCorrectionRules,
            writingStyles: writingStylePresets,
            appProfiles: dictationAppProfiles)
    }

    func saveWritingStylePresets(_ presets: [WritingStylePreset]) throws {
        try WritingStylePresetStore.save(presets)
        writingStylePresets = presets
    }

    func clearAppProfileStyleReference(_ styleID: UUID) {
        dictationAppProfiles = dictationAppProfiles.map { profile in
            guard profile.writingStylePresetID == styleID else { return profile }
            var updated = profile
            updated.writingStylePresetID = nil
            return updated
        }
        if activeDictationWritingStylePresetID == styleID {
            activeDictationWritingStylePresetID = nil
        }
    }

    func exportSessions() {
        do {
            guard let url = try recorder.exportAllSessions() else {
                dataMessage = "No session logs to export."
                return
            }
            dataMessage = "Session logs exported to \(url.lastPathComponent)."
        } catch {
            dataMessage = "Session export failed: \(error.localizedDescription)"
        }
    }

    func deleteSessionLogs() {
        do {
            try recorder.deleteAllSessions()
            dropHistoryAudio()
            dataMessage = "Session logs and local audio files deleted."
        } catch {
            dataMessage = "Session deletion failed: \(error.localizedDescription)"
        }
    }

    func deleteTemplate(_ id: Template.ID) {
        dataset.templates.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try TemplateStore.save(dataset, to: TemplateStore.url)
            datasetArchiveUnreadable = false
            datasetRecoveryCopyURL = nil
            if dataMessage?.contains("Silent Lab dataset") == true { dataMessage = nil }
            rebuildClassifier()
            return true
        } catch {
            dataMessage = "Couldn’t save Silent Lab training data: \(error.localizedDescription)"
            rebuildClassifier()
            return false
        }
    }

    private func rebuildClassifier() {
        let silentTemplates = usableTemplates(condition: .silent)
        classifier = TemplateClassifier(templates: silentTemplates, featureSet: featureSet)
        evaluation = nil
        refreshSilentEvidence(silentTemplates)
        syncCaptureMode()
    }

    /// Re-runs the evidence check in the background for the templates the classifier now uses.
    private func refreshSilentEvidence(_ templates: [Template]) {
        silentEvidenceTask?.cancel()
        silentEvidence = nil
        guard templates.count >= Self.minimumEvidenceTemplates else {
            isCheckingSilentEvidence = false
            return
        }
        isCheckingSilentEvidence = true
        let featureSet = featureSet
        silentEvidenceTask = Task {
            // Coalesce bursts of edits (several deletes in a row) into one run.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                Evaluation.run(templates: templates, featureSet: featureSet)
            }.value
            guard !Task.isCancelled else { return }
            self.silentEvidence = result
            self.isCheckingSilentEvidence = false
            self.syncCaptureMode()
        }
    }

    func evaluate() {
        guard !isEvaluating else { return }
        isEvaluating = true
        let templates = templatesForSelectedCondition
        let featureSet = featureSet
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Evaluation.run(templates: templates, featureSet: featureSet)
            }.value
            self.evaluation = result
            if self.trainingCondition == .silent, featureSet == self.featureSet,
               templates == self.usableTemplates(condition: .silent) {
                self.silentEvidenceTask?.cancel()
                self.silentEvidence = result
                self.isCheckingSilentEvidence = false
            }
            self.isEvaluating = false
            self.syncCaptureMode()
        }
    }

    var templatesForSelectedCondition: [Template] {
        usableTemplates(condition: trainingCondition)
    }

    // MARK: Decode transcript

    var transcript: String {
        decoded.filter(\.prediction.accepted).map(\.text).joined(separator: " ")
    }

    nonisolated static let minimumEvidenceTemplates = 50

    var isMotionInferenceEnabled: Bool { Self.evidenceUnlocksSilentUse(silentEvidence) }

    /// The silent-mouthing evidence gate: enough takes, better than chance, unlikely to be luck,
    /// and still better than the baseline on a session it never trained on.
    nonisolated static func evidenceUnlocksSilentUse(_ evaluation: Evaluation?) -> Bool {
        guard let evaluation,
              let holdout = evaluation.sessionHoldoutAccuracy,
              let holdoutBaseline = evaluation.sessionHoldoutChance else { return false }
        return evaluation.templateCount >= minimumEvidenceTemplates &&
            evaluation.accuracy > evaluation.chance &&
            evaluation.pValue < 0.05 &&
            evaluation.sessionHoldoutComplete && evaluation.sessionHoldoutSessions >= 2 &&
            holdout > holdoutBaseline
    }

    /// Types an accepted word into the frontmost app when that app is not HushKey. With HushKey in front
    /// the word stays in the transcript and the insert shortcut can place it later.
    private func typeSilentWordIfAllowed(_ word: DecodedWord) -> Bool {
        guard silentTypesIntoFrontApp, insertion.isEnabled, captureGate.owner == nil, !NSApp.isActive,
              insertion.insert(word.text) else { return false }
        lastInsertedPredictionID = word.id
        return true
    }

    func clearDecoded() {
        decoded.removeAll()
        lastSegment = []
        lastInsertedPredictionID = nil
    }

    func insertLatestPrediction() {
        guard screen == .use else {
            insertion.report("Open Silent Use before inserting a trained-word prediction.")
            return
        }
        guard captureGate.owner == nil else {
            insertion.report("Stop active capture before inserting a trained-word prediction.")
            return
        }
        guard let word = decoded.last, word.prediction.accepted else {
            insertion.report("No accepted prediction is ready to insert.")
            return
        }
        guard word.id != lastInsertedPredictionID else {
            insertion.report("This prediction was already inserted once.")
            return
        }
        if insertion.insert(word.text) { lastInsertedPredictionID = word.id }
    }

    func insertLatestOutput() {
        guard captureGate.owner != .meeting else {
            insertion.report("Stop meeting capture before inserting text.")
            return
        }
        guard selectedTextEditTarget == nil, !isStartingSelectedTextEdit,
              !isSelectedTextEditCapturing, !isFinalizingSelectedTextEdit else {
            insertion.report("Review the selected-text preview in Transforms before applying it.")
            return
        }
        switch Self.insertionOutputRoute(for: screen) {
        case .dictation:
            insertDictationText()
        case .silentPrediction:
            insertLatestPrediction()
        case .unavailable:
            insertion.report("Open Dictation or Silent Use before inserting text.")
        }
    }

    static func insertionOutputRoute(for screen: Screen) -> InsertionOutputRoute {
        switch screen {
        case .dictation, .transforms: .dictation
        case .use: .silentPrediction
        default: .unavailable
        }
    }

    func insertDictationText() {
        Task { await insertDictationTextAsync() }
    }

    private func insertDictationTextAsync() async {
        guard selectedTextEditTarget == nil else {
            insertion.report("Review the selected-text preview in Transforms before applying it.")
            return
        }
        if let reason = DictationInsertionGate.blockedReason(
            audioIsRunning: audio.isRunning,
            recognitionIsRunning: transcriber.isRunning,
            isFinalizing: isFinalizingDictation || transcriber.isFinalizing,
            meetingCaptureIsActive: captureGate.owner == .meeting
        ) {
            insertion.report(reason)
            return
        }
        let text = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            insertion.report("Dictate something first.")
            return
        }
        guard !didInsertCurrentDictation else {
            insertion.report("This transcript was already inserted once.")
            return
        }

        if let target = capturedInsertionTarget {
            guard let app = dictationTargetApp else {
                insertion.report("The original app is no longer available. Nothing was inserted.")
                return
            }
            isInsertingDictation = true
            defer { isInsertingDictation = false }
            if await insertion.insert(text, into: target) {
                didInsertCurrentDictation = true
                dictationNotice = nil
                return
            }
            if insertion.requiresReviewAfterInsertion {
                dictationNotice = DictationRecovery.pasteUnconfirmed(insertion.status, canPasteAgain: false)
                return
            }
            guard let pasteTarget = capturedPasteTarget,
                  insertion.focusState(of: target).fieldIsFocused else {
                dictationNotice = DictationRecovery.insertionFailed(
                    insertion.status, canPasteAgain: capturedPasteTarget != nil)
                return
            }
            switch await insertion.paste(text, into: app, target: pasteTarget) {
            case .inserted:
                didInsertCurrentDictation = true
                dictationNotice = nil
            case .unconfirmed:
                dictationNotice = DictationRecovery.pasteUnconfirmed(insertion.status, canPasteAgain: false)
            case .unavailable:
                dictationNotice = DictationRecovery.insertionFailed(insertion.status, canPasteAgain: false)
            }
            return
        }

        if insertion.insert(text) {
            didInsertCurrentDictation = true
            dictationNotice = nil
        } else if insertion.requiresReviewAfterInsertion {
            dictationNotice = DictationRecovery.pasteUnconfirmed(insertion.status, canPasteAgain: false)
        }
    }

    var canInsertIntoCapturedTarget: Bool {
        capturedInsertionTarget != nil && selectedTextEditTarget == nil && insertion.isEnabled && !isInsertingDictation &&
            !didInsertCurrentDictation && !audio.isRunning && !isFinalizingDictation &&
            !transcriber.isRunning && !transcriber.isFinalizing && captureGate.owner != .meeting
    }

    var canPreviewSelectedTextEdit: Bool {
        selectedTextEditTarget != nil && !selectedTextEditOriginal.isEmpty &&
            !selectedTextEditInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !selectedTextEditApplied &&
            !isSelectedTextEditCapturing && !isFinalizingSelectedTextEdit &&
            !isGeneratingSelectedTextEdit && !audio.isRunning &&
            localTransformService.modelIsAvailable
    }

    var canApplySelectedTextEdit: Bool {
        selectedTextEditTarget != nil && insertion.isEnabled && !selectedTextEditApplied &&
            !isApplyingSelectedTextEdit && !isSelectedTextEditCapturing &&
            !isFinalizingSelectedTextEdit && !audio.isRunning &&
            !selectedTextEditDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            selectedTextEditDraft.trimmingCharacters(in: .whitespacesAndNewlines) !=
                selectedTextEditOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func updateSelectedTextEditInstruction(_ instruction: String) {
        guard selectedTextEditInstruction != instruction else { return }
        selectedTextEditInstruction = instruction
        selectedTextEditDraft = ""
        selectedTextEditStatus = nil
        selectedTextEditGeneration += 1
    }

    func updateSelectedTextEditDraft(_ draft: String) {
        guard !selectedTextEditApplied else { return }
        selectedTextEditDraft = draft
    }

    func previewSelectedTextEdit() async {
        guard canPreviewSelectedTextEdit else { return }
        let source = selectedTextEditOriginal
        let instruction = selectedTextEditInstruction
        selectedTextEditGeneration += 1
        let generation = selectedTextEditGeneration
        selectedTextEditDraft = ""
        selectedTextEditStatus = "Creating a preview on this Mac…"
        isGeneratingSelectedTextEdit = true
        defer { isGeneratingSelectedTextEdit = false }
        do {
            let draft = try await localTransformService.transformSelectedText(source, instruction: instruction)
            guard generation == selectedTextEditGeneration,
                  selectedTextEditOriginal == source,
                  selectedTextEditInstruction == instruction else { return }
            selectedTextEditDraft = draft
            selectedTextEditStatus = draft.trimmingCharacters(in: .whitespacesAndNewlines) ==
                source.trimmingCharacters(in: .whitespacesAndNewlines)
                ? "The preview matches the original selection. Nothing needs replacing."
                : "Preview ready. The original selection is unchanged until you apply it."
        } catch {
            guard generation == selectedTextEditGeneration else { return }
            selectedTextEditDraft = ""
            selectedTextEditStatus = error.localizedDescription
        }
    }

    func applySelectedTextEdit() async {
        guard canApplySelectedTextEdit, let target = selectedTextEditTarget else { return }
        let generation = selectedTextEditGeneration
        let draft = selectedTextEditDraft
        isApplyingSelectedTextEdit = true
        selectedTextEditStatus = "Checking the original app and selection…"
        defer { isApplyingSelectedTextEdit = false }
        let inserted = await insertion.insert(draft, into: target)
        guard generation == selectedTextEditGeneration else { return }
        if inserted {
            selectedTextEditApplied = true
            selectedTextEditStatus = "Applied once. You can undo with ⌥⇧U while the same field stays focused."
        } else {
            selectedTextEditStatus = insertion.status
        }
    }

    func clearSelectedTextEdit() {
        guard !isSelectedTextEditCapturing, !isFinalizingSelectedTextEdit,
              !isApplyingSelectedTextEdit else { return }
        selectedTextEditGeneration += 1
        selectedTextEditTarget = nil
        selectedTextEditTargetName = nil
        selectedTextEditOriginal = ""
        selectedTextEditInstruction = ""
        selectedTextEditDraft = ""
        selectedTextEditStatus = nil
        selectedTextEditApplied = false
        selectedEditTranscriber.clear()
    }

    func insertDictationTextIntoCapturedTarget() async {
        guard selectedTextEditTarget == nil else {
            insertion.report("Review the selected-text preview in Transforms before applying it.")
            return
        }
        if let reason = DictationInsertionGate.blockedReason(
            audioIsRunning: audio.isRunning,
            recognitionIsRunning: transcriber.isRunning,
            isFinalizing: isFinalizingDictation || transcriber.isFinalizing,
            meetingCaptureIsActive: captureGate.owner == .meeting
        ) {
            insertion.report(reason)
            return
        }
        guard let target = capturedInsertionTarget else {
            insertion.report("Start dictation with the global shortcut while the target text field is focused to enable safe insertion here.")
            return
        }
        let text = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            insertion.report("Dictate something first.")
            return
        }
        guard !didInsertCurrentDictation, !isInsertingDictation else {
            insertion.report("This transcript was already inserted once.")
            return
        }
        isInsertingDictation = true
        defer { isInsertingDictation = false }
        if await insertion.insert(text, into: target) {
            didInsertCurrentDictation = true
            dictationNotice = nil
            return
        }
        if insertion.requiresReviewAfterInsertion {
            dictationNotice = DictationRecovery.pasteUnconfirmed(insertion.status, canPasteAgain: false)
            return
        }
        guard let app = dictationTargetApp,
              let pasteTarget = capturedPasteTarget,
              insertion.focusState(of: target).fieldIsFocused else {
            dictationNotice = DictationRecovery.insertionFailed(
                insertion.status, canPasteAgain: capturedPasteTarget != nil)
            return
        }
        switch await insertion.paste(text, into: app, target: pasteTarget) {
        case .inserted:
            didInsertCurrentDictation = true
            dictationNotice = nil
        case .unconfirmed:
            dictationNotice = DictationRecovery.pasteUnconfirmed(insertion.status, canPasteAgain: false)
        case .unavailable:
            dictationNotice = DictationRecovery.insertionFailed(insertion.status, canPasteAgain: false)
        }
    }

    func undoLastInsertion() {
        if insertion.undoLastInsertion() { didInsertCurrentDictation = false }
    }

    func copyDictationText() {
        let text = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        insertion.report("Transcript copied to the clipboard.")
    }

    func copyDictation(_ entry: DictationHistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        dictationHistoryMessage = "Copied to the clipboard."
    }

    /// Deletes one entry right away and keeps it in memory for a few seconds so it can be undone.
    func deleteDictation(_ entry: DictationHistoryEntry) {
        guard let index = dictationHistory.firstIndex(where: { $0.id == entry.id }) else { return }
        let deleted = dictationHistory[index]
        let remaining = dictationHistory.filter { $0.id != entry.id }
        do {
            if remaining.isEmpty { try DictationHistoryStore.delete(at: dictationHistoryURL) }
            else { try DictationHistoryStore.save(remaining, to: dictationHistoryURL) }
            dictationHistory = remaining
            if let previous = deletedDictation, previous.entry.id != entry.id { forgetDeletedAudio(previous.entry.id) }
            deletedDictation = DeletedDictation(entry: deleted, index: index)
            if currentDictationHistoryEntryID == entry.id {
                cancelPendingDictationHistorySave()
                currentDictationHistoryEntryID = nil
                lastSavedDictationText = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            dictationHistoryMessage = nil
        } catch {
            dictationHistoryMessage = "Could not delete this dictation: \(error.localizedDescription)"
        }
    }

    // MARK: History row actions

    /// Puts the last deleted entry back where it was.
    func undoDeleteDictation() {
        guard let deleted = deletedDictation else { return }
        let restored = deleted.restoring(into: dictationHistory)
        do {
            try DictationHistoryStore.save(restored, to: dictationHistoryURL)
            dictationHistory = restored
            deletedDictation = nil
            // The open transcript was this entry and hasn't changed since: keep saving into it.
            if currentDictationHistoryEntryID == nil,
               transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines) == deleted.entry.text,
               lastSavedDictationText == deleted.entry.text {
                currentDictationHistoryEntryID = deleted.entry.id
            }
            if dictationHistoryRecoveryCopyURL == nil { dictationHistoryMessage = nil }
        } catch {
            dictationHistoryMessage = "Could not restore this dictation: \(error.localizedDescription)"
        }
    }

    /// Ends the Undo window for a deletion; called when the bar times out.
    func expireDeletedDictation(_ id: UUID) {
        guard deletedDictation?.entry.id == id else { return }
        deletedDictation = nil
        forgetDeletedAudio(id)
    }

    /// Shows what the recognizer heard before cleanup ("Undo cleanup"), or puts the cleanup back.
    func toggleCleanup(_ entry: DictationHistoryEntry) {
        guard canClearDictationHistory,
              let current = dictationHistory.first(where: { $0.id == entry.id }),
              let updated = current.undoingCleanup() ?? current.redoingCleanup() else { return }
        let entries = dictationHistory.map { $0.id == updated.id ? updated : $0 }
        do {
            try DictationHistoryStore.save(entries, to: dictationHistoryURL)
            dictationHistory = entries
            if currentDictationHistoryEntryID == updated.id {
                // The editor shows this entry: keep it in step so autosave doesn't undo the change.
                cancelPendingDictationHistorySave()
                transcriber.replaceText(updated.text)
                lastSavedDictationText = updated.text
                clearLocalTransformUndo()
            }
            if dictationHistoryRecoveryCopyURL == nil { dictationHistoryMessage = nil }
        } catch {
            dictationHistoryMessage = "Could not change this dictation: \(error.localizedDescription)"
        }
    }

    /// The engine History would use to re-run this entry's audio.
    func retranscribeEngine(for entry: DictationHistoryEntry) -> DictationEngine? {
        guard let held = heldHistoryAudio, held.entryID == entry.id else { return nil }
        return held.engine == .parakeet ? .appleSpeech : .parakeet
    }

    func retranscribeState(for entry: DictationHistoryEntry) -> DictationHistoryActionState {
        let other = retranscribeEngine(for: entry)
        var problem: String?
        switch other {
        case .parakeet?:
            if !parakeet.isDownloaded { problem = "Download Parakeet in Settings to re-transcribe" }
            else if !parakeet.model.supports(localeIdentifier: activeDictationLanguageIdentifier) {
                problem = "Parakeet doesn’t know this language"
            }
        case .appleSpeech?:
            if SFSpeechRecognizer.authorizationStatus() != .authorized { problem = "Allow Speech Recognition to re-transcribe" }
        case nil:
            break
        }
        return DictationRetranscribeGate.state(
            hasAudio: heldHistoryAudioEntryID == entry.id && other != nil,
            hadAudio: droppedHistoryAudioEntryIDs.contains(entry.id),
            isBusy: !canClearDictationHistory || isStartingSelectedTextEdit || isFinalizingSelectedTextEdit
                || retranscribingDictationID != nil,
            otherEngineProblem: problem)
    }

    /// Runs the latest dictation's kept audio through the other engine and replaces the entry's
    /// text. Nothing is typed into another app.
    func retranscribeDictation(_ entry: DictationHistoryEntry) async {
        guard retranscribeState(for: entry).isAvailable, let held = heldHistoryAudio, held.entryID == entry.id,
              let engine = retranscribeEngine(for: entry) else { return }
        guard captureGate.claim(.dictation) else {
            dictationHistoryMessage = "Meeting capture is active. Stop it before re-transcribing."
            return
        }
        // Save any edit open in the editor first, then make this entry the open one.
        cancelPendingDictationHistorySave()
        saveCurrentDictation()
        let previousHasTarget = dictationHasTarget
        currentDictationHistoryEntryID = entry.id
        transcriber.replaceText(entry.text)
        rawDictationText = entry.rawText ?? entry.text
        clearLocalTransformUndo()
        lastSavedDictationText = entry.text
        lastDictationDuration = entry.duration
        dictationNotice = nil
        dictationHasTarget = false
        finishesWithoutTyping = true
        retranscribingDictationID = entry.id
        isFinalizingDictation = true
        activeDictationUsesParakeet = engine == .parakeet
        activeDictationEngine = engine
        finishingAudioOverride = held.buffers
        defer {
            dictationHasTarget = previousHasTarget
            finishesWithoutTyping = false
            retranscribingDictationID = nil
            // Nothing heard: the entry wasn't changed, so the editor shows it again.
            if transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transcriber.replaceText(entry.text)
                lastSavedDictationText = entry.text
            }
        }
        if engine == .parakeet {
            if let text = await parakeetText(held.buffers) {
                activeParakeetNeedsReview = false
                await finishDictation(rawText: text, recognitionError: nil)
            } else {
                endRetranscribe(failure: "Parakeet couldn’t transcribe this recording. The entry is unchanged.")
            }
            return
        }
        let started = await transcriber.transcribe(recorded: held.buffers, localeIdentifier: activeDictationLanguageIdentifier,
                                                   contextualStrings: lastDictationContextualStrings)
        guard started else {
            endRetranscribe(failure: "Apple Speech couldn’t start: \(transcriber.error ?? "speech recognition is unavailable"). The entry is unchanged.")
            return
        }
        let rawText = await transcriber.waitForFinalization()
        await finishDictation(rawText: rawText, recognitionError: transcriber.error)
    }

    private func endRetranscribe(failure: String) {
        finishingAudioOverride = nil
        isFinalizingDictation = false
        captureGate.release(.dictation)
        dictationHistoryMessage = "Could not re-transcribe: \(failure)"
    }

    /// "Paste again" from History: only the latest dictation, only into the field it came from.
    func pasteAgainState(for entry: DictationHistoryEntry) -> DictationHistoryActionState {
        DictationHistoryPasteGate.state(
            isLatestDictation: currentDictationHistoryEntryID == entry.id,
            hasTarget: capturedInsertionTarget != nil || capturedPasteTarget != nil,
            textMatches: transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines) == entry.text,
            isBusy: !canClearDictationHistory, alreadyInserted: didInsertCurrentDictation,
            insertionEnabled: insertion.isEnabled)
    }

    /// Brings the original app forward, then types the dictation only if its field still has focus.
    func pasteDictationAgain(_ entry: DictationHistoryEntry) async {
        guard pasteAgainState(for: entry).isAvailable else { return }
        dictationTargetApp?.activate()
        try? await Task.sleep(for: .milliseconds(350))
        await pasteLastDictationAgain()
    }

    private func holdHistoryAudio(_ buffers: [AVAudioPCMBuffer], for entryID: UUID, engine: DictationEngine) {
        if let previous = heldHistoryAudio?.entryID, previous != entryID { droppedHistoryAudioEntryIDs.insert(previous) }
        heldHistoryAudio = (entryID, buffers, engine)
        heldHistoryAudioEntryID = entryID
        droppedHistoryAudioEntryIDs.remove(entryID)
    }

    private func dropHistoryAudio() {
        guard let entryID = heldHistoryAudio?.entryID else { return }
        heldHistoryAudio = nil
        heldHistoryAudioEntryID = nil
        droppedHistoryAudioEntryIDs.insert(entryID)
    }

    /// A deletion that can no longer be undone frees its audio too.
    private func forgetDeletedAudio(_ entryID: UUID) {
        if heldHistoryAudio?.entryID == entryID {
            heldHistoryAudio = nil
            heldHistoryAudioEntryID = nil
        }
        droppedHistoryAudioEntryIDs.remove(entryID)
    }

    @discardableResult
    func applyLocalTransform(_ transformedText: String, basedOn sourceText: String) -> Bool {
        guard !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing,
              transcriber.text == sourceText else { return false }
        let transformed = transformedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transformed.isEmpty, transformed != normalizedSource else { return false }
        transformUndoOriginalText = sourceText
        transformUndoOutputText = transformed
        transcriber.replaceText(transformed)
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        saveCurrentDictation()
        return true
    }

    func undoLocalTransform() {
        guard canUndoLocalTransform, let original = transformUndoOriginalText else { return }
        transcriber.replaceText(original)
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        saveCurrentDictation()
    }

    func startNewDictation() async {
        guard NSApp.modalWindow == nil else { return }
        guard !isStartingDictation else { return }
        guard !isFinalizingDictation, !transcriber.isFinalizing else { return }
        guard !isStartingSelectedTextEdit, !isFinalizingSelectedTextEdit else { return }
        if audio.isRunning {
            if isSelectedTextEditCapturing {
                selectedTextEditShortcutHeld = false
                stopSelectedTextEditCapture()
                return
            }
            stopDictation()
        }
        clearSelectedTextEdit()
        cancelPendingDictationHistorySave()
        saveCurrentDictation()
        // Stay on the current page: fn works from anywhere, and switching here closed open sheets.
        capturedInsertionTarget = nil
        capturedPasteTarget = nil
        capturedInsertionTargetName = nil
        transcriber.clear()
        rawDictationText = ""
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        lastSavedDictationText = nil
        currentDictationHistoryEntryID = nil
        await startDictation()
    }

    func toggleDictation() async {
        if isStartingDictation {
            stopWhileStarting()
        } else if isStartingSelectedTextEdit {
            selectedTextEditShortcutHeld = false
            selectedTextEditStatus = "Voice edit start cancelled. Your selected text is unchanged."
        } else if isSelectedTextEditCapturing {
            selectedTextEditShortcutHeld = false
            stopSelectedTextEditCapture()
        } else if audio.isRunning {
            stopDictation()
        } else {
            await startNewDictation()
        }
    }

    func clearDictationHistory() {
        guard canClearDictationHistory else {
            dictationHistoryMessage = "Stop dictation before clearing history so the active transcript can finish safely."
            return
        }
        let recoveryCopyURL = dictationHistoryRecoveryCopyURL
        do {
            try DictationHistoryStore.delete(at: dictationHistoryURL)
            cancelPendingDictationHistorySave()
            dictationHistory.removeAll()
            deletedDictation = nil
            dropHistoryAudio()
            droppedHistoryAudioEntryIDs = []
            dictationHistoryRecoveryCopyURL = nil
            dictationHistoryArchiveUnreadable = false
            currentDictationHistoryEntryID = nil
            lastSavedDictationText = nil
            dictationHistoryMessage = "Saved transcript history was deleted from this Mac." +
                (recoveryCopyURL.map { " Recovery copy: \($0.path)" } ?? "")
        } catch {
            dictationHistoryMessage = "Could not delete transcript history: \(error.localizedDescription)"
            return
        }
        if !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing {
            transcriber.clear()
            capturedInsertionTarget = nil
            capturedPasteTarget = nil
            capturedInsertionTargetName = nil
            rawDictationText = ""
            clearLocalTransformUndo()
            didInsertCurrentDictation = false
            insertion.clearUndoRecord()
        }
    }

    func restoreDictation(_ entry: DictationHistoryEntry, useRawText: Bool = false) {
        guard !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing else { return }
        cancelPendingDictationHistorySave()
        let restoredText = useRawText ? (entry.rawText ?? entry.text) : entry.text
        transcriber.replaceText(restoredText)
        capturedInsertionTarget = nil
        capturedPasteTarget = nil
        capturedInsertionTargetName = nil
        activeDictationTarget = nil
        dictationTargetApp = nil
        dictationHasTarget = false
        activeDictationProfileName = nil
        activeDictationWritingStylePresetID = nil
        rawDictationText = entry.rawText ?? entry.text
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        lastSavedDictationText = restoredText
        currentDictationHistoryEntryID = nil
        lastDictationDuration = nil
        dismissDictationNotice()
        screen = .dictation
    }

    func restoreRawTranscript() {
        guard !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing,
              !rawDictationText.isEmpty else { return }
        editCurrentDictation(rawDictationText)
    }

    func editCurrentDictation(_ text: String) {
        guard !audio.isRunning, !isFinalizingDictation, !transcriber.isRunning,
              !transcriber.isFinalizing, transcriber.text != text else { return }
        transcriber.replaceText(text)
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        clearLocalTransformUndo()
        scheduleCurrentDictationSave()
    }

    func clearCurrentDictation() {
        guard !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing else { return }
        cancelPendingDictationHistorySave()
        transcriber.clear()
        capturedInsertionTarget = nil
        capturedPasteTarget = nil
        capturedInsertionTargetName = nil
        rawDictationText = ""
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        lastSavedDictationText = nil
        currentDictationHistoryEntryID = nil
        dismissDictationNotice()
    }

    func requestNearbyTextAccess() {
        _ = insertion.requestAccessibilityAccessForContext()
    }

    @discardableResult
    func saveDictationAppProfile(appName: String, bundleIdentifier: String, mode: DictationMode,
                                 vocabulary: String, languageIdentifier: String? = nil,
                                 snippets: String? = nil, correctionRules: String? = nil,
                                 cleansFillers: Bool? = nil, writingStylePresetID: UUID? = nil) -> Bool {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIdentifier = DictationAppProfile.normalizedBundleIdentifier(identifier)
        let profileAlreadyExists = dictationAppProfiles.contains {
            DictationAppProfile.normalizedBundleIdentifier($0.bundleIdentifier) == normalizedIdentifier
        }
        guard !name.isEmpty, name.count <= 80,
              DictationAppProfile.isValidBundleIdentifier(identifier),
              mode != .automatic, vocabulary.utf8.count <= DictationAppProfile.maximumCustomizationBytes,
              (profileAlreadyExists || dictationAppProfiles.count < HushKeyPersonalDataBackup.maximumAppProfiles),
              languageIdentifier.map({ language in
                  DictationLanguage.onDevice.contains { $0.identifier == language }
              }) ?? true,
              snippets.map({ $0.utf8.count <= DictationAppProfile.maximumCustomizationBytes && DictationSnippetExpander.validation(for: $0).invalidLines.isEmpty }) ?? true,
              correctionRules.map({ $0.utf8.count <= DictationAppProfile.maximumCustomizationBytes && DictationCorrectionRules.validation(for: $0).invalidLines.isEmpty }) ?? true,
              writingStylePresetID.map({ id in writingStylePresets.contains { $0.id == id } }) ?? true else { return false }
        let profile = DictationAppProfile(appName: name, bundleIdentifier: identifier,
                                          mode: mode, vocabulary: vocabulary,
                                          languageIdentifier: languageIdentifier,
                                          snippets: snippets,
                                          correctionRules: correctionRules,
                                          cleansFillers: cleansFillers,
                                          writingStylePresetID: writingStylePresetID)
        dictationAppProfiles = DictationAppProfile.upserting(profile, into: dictationAppProfiles)
        return true
    }

    func deleteDictationAppProfile(bundleIdentifier: String) {
        let identifier = DictationAppProfile.normalizedBundleIdentifier(bundleIdentifier)
        dictationAppProfiles.removeAll { DictationAppProfile.normalizedBundleIdentifier($0.bundleIdentifier) == identifier }
    }

    private func startDictation() async {
        guard !isFinalizingDictation, !transcriber.isFinalizing else { return }
        guard !meetingNotes.isStarting, !meetingNotes.isCapturing, !meetingNotes.isFinalizing else {
            insertion.report("Meeting capture is active. Stop it before starting dictation.")
            return
        }
        guard captureGate.claim(.dictation) else {
            insertion.report("Meeting capture is active. Stop it before starting dictation.")
            return
        }
        isStartingDictation = true
        stopsWhenStarted = false
        defer { isStartingDictation = false }
        var timing = StartTiming()
        dictationStartGeneration += 1
        let generation = dictationStartGeneration
        dictationNotice = nil
        showsFinishedTranscript = false
        retainedAudio.reset()
        dropHistoryAudio()
        let target = NSWorkspace.shared.frontmostApplication
        let isHushKey = target?.bundleIdentifier == "com.ruddvz.hushkey"
        activeDictationTarget = isHushKey ? nil : target?.localizedName
        timing.mark("reset")

        // Started here, awaited below. The engine itself starts on AudioService's queue; this
        // MainActor call runs once the main actor next suspends.
        async let audioStartup: Void = audio.start()

        capturedInsertionTarget = isHushKey ? nil : insertion.captureInsertionTarget()
        timing.mark("axTarget")
        capturedPasteTarget = nil
        if !isHushKey, let target {
            capturedPasteTarget = insertion.capturePasteTarget(into: target)
        }
        timing.mark("pasteTarget")
        capturedInsertionTargetName = capturedInsertionTarget?.applicationName
        dictationTargetApp = isHushKey ? nil : target
        dictationHasTarget = insertion.isEnabled && (capturedInsertionTarget != nil || capturedPasteTarget != nil)
        Logger(subsystem: "com.ruddvz.hushkey", category: "insertion")
            .notice("start insertTarget=\(self.capturedInsertionTarget != nil) pasteTarget=\(self.capturedPasteTarget != nil)")
        timing.mark("logFocus")
        let targetBundleIdentifier = isHushKey ? nil : target?.bundleIdentifier
        let profileSettings = DictationAppProfile.resolve(
            requestedMode: dictationMode,
            bundleIdentifier: targetBundleIdentifier,
            profiles: dictationAppProfiles,
            globalVocabulary: dictationTerms,
            globalLanguageIdentifier: dictationLanguage,
            globalSnippets: dictationSnippets,
            globalCorrectionRules: dictationCorrectionRules,
            globalCleansFillers: cleansDictationFillers)
        activeDictationMode = profileSettings.mode
        activeDictationTone = dictationToneSettings.tone(forBundle: targetBundleIdentifier, mode: profileSettings.mode)
        activeUsageCategory = UsageCategory.category(mode: profileSettings.mode, bundleIdentifier: targetBundleIdentifier)
        activeDictationLanguageIdentifier = profileSettings.languageIdentifier
        activeDictationSnippets = profileSettings.snippets
        activeDictationCorrectionRules = profileSettings.correctionRules
        activeDictationCleansFillers = profileSettings.cleansFillers
        activeDictationAppliesSpokenCorrections = appliesSpokenCorrections
        activeDictationUsesSmartCleanup = polishesWithAppleIntelligence && profileSettings.cleansFillers &&
            profileSettings.mode != .code
        timing.mark("profile")
        captureDictationProfileName = profileSettings.appName
        captureDictationWritingStylePresetID = profileSettings.writingStylePresetID
        let nearbyHints = usesNearbyTextHints ? insertion.nearbyContextHints() : []
        usedNearbyTextHints = !nearbyHints.isEmpty
        timing.mark("nearbyText")
        let usesParakeet = usesParakeet(for: activeDictationLanguageIdentifier)
        activeDictationUsesParakeet = usesParakeet
        activeDictationEngine = usesParakeet ? .parakeet : .appleSpeech
        activeParakeetNeedsReview = false
        lastParakeetConfidence = nil
        lastParakeetPeakLevel = nil
        if usesParakeet { parakeet.warmUp() }
        timing.mark("parakeetWarmUp")
        // With Parakeet, Apple Speech only shows words while you talk, and only if it's already allowed.
        let showsApplePreview = !usesParakeet || SFSpeechRecognizer.authorizationStatus() == .authorized

        // Open the microphone while Speech gets ready, and buffer what it hears, so words
        // spoken during the start aren't lost.
        async let speechPreparation = showsApplePreview
            ? transcriber.prepare(localeIdentifier: activeDictationLanguageIdentifier) : false
        await audioStartup
        timing.mark("micOpen")
        guard generation == dictationStartGeneration else {
            timing.report("superseded")
            return
        }
        if audio.isRunning {
            if showsApplePreview { transcriber.beginBuffering(sink: audio.sink) }
            retainedAudioSinkID = audio.sink.add { [retainedAudio] buffer, _ in retainedAudio.append(buffer) }
        }
        let speechReady = await speechPreparation
        timing.mark("speechPrepare")
        guard generation == dictationStartGeneration else {
            timing.report("superseded")
            return
        }
        guard speechReady || usesParakeet, audio.isRunning else {
            timing.report("failed")
            transcriber.stop()
            audio.stop()
            stopRetainingAudio(keep: false)
            captureGate.release(.dictation)
            if !speechReady {
                dictationNotice = SFSpeechRecognizer.authorizationStatus() != .authorized
                    ? DictationRecovery.permissionNeeded(.speechRecognition)
                    : DictationRecovery.notice(
                        audioError: nil, transcriberError: transcriber.error ?? "Local speech recognition is unavailable.",
                        transcript: "", hasRetainedAudio: false)
            } else {
                dictationNotice = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
                    ? DictationRecovery.permissionNeeded(.microphone)
                    : DictationRecovery.notice(audioError: audio.error ?? "The microphone did not start.",
                                               transcriberError: nil, transcript: "", hasRetainedAudio: false)
            }
            return
        }
        lastDictationMicrophoneName = audio.activeDeviceName
        playDictationCue(.start)
        muteOutputForDictation()
        timing.mark("cueAndMute")
        // Only needed when the dictation finishes, so prewarm asynchronously off the critical start path.
        if usesSmartCleanup {
            Task { @MainActor [weak self] in
                guard let self, self.dictationStartGeneration == generation else { return }
                self.smartCleanupSession = DictationSmartCleanup.prepare()
            }
        }
        timing.mark("smartCleanup")
        dictationStartedAt = Date()
        lastDictationDuration = nil
        let customWords = profileSettings.vocabulary
        lastDictationContextualStrings = DictationContextHints.prioritized(customWords: customWords,
                                                                           modeHints: Self.modeHints(for: activeDictationMode),
                                                                           nearbyHints: nearbyHints,
                                                                           learnedWords: dataset.vocabulary)
        let started = speechReady
            ? await transcriber.start(sink: audio.sink, localeIdentifier: activeDictationLanguageIdentifier,
                                      contextualStrings: lastDictationContextualStrings)
            : false
        timing.mark("speechStart")
        timing.report(started ? "ok" : "noPreview")
        guard generation == dictationStartGeneration else {
            timing.report("superseded")
            return
        }
        guard audio.isRunning else {
            transcriber.stop()
            restoreOutputAfterDictation()
            audio.stop()
            stopRetainingAudio(keep: false)
            captureGate.release(.dictation)
            return
        }
        if started { beginLiveTyping(usesParakeet: usesParakeet) }
        if !started, usesParakeet {
            // No live preview; Parakeet still gets the whole recording on release.
            transcriber.stop()
            if stopsWhenStarted {
                stopsWhenStarted = false
                stopDictation()
            }
        } else if !started {
            restoreOutputAfterDictation()
            audio.stop()
            stopRetainingAudio(keep: false)
            captureGate.release(.dictation)
            dictationNotice = DictationRecovery.notice(
                audioError: nil, transcriberError: transcriber.error ?? "Speech recognition did not start.",
                transcript: "", hasRetainedAudio: false)
        } else if stopsWhenStarted {
            stopsWhenStarted = false
            stopDictation()
        }
    }

    private func stopDictation() {
        guard audio.isRunning else { return }
        restoreOutputAfterDictation()
        dictationStartGeneration += 1
        isFinalizingDictation = true
        // The rest is typed once, at the end, from the final transcript.
        liveTypingTimer?.cancel()
        liveTypingTimer = nil
        if transcriber.isRunning { transcriber.beginFinalization() }
        else { transcriber.stop() }
        audio.stop()
        stopRetainingAudio(keep: true)
        functionKey.reset()
        lastDictationDuration = dictationStartedAt.map { Date().timeIntervalSince($0) }
        dictationStartedAt = nil
        let usesParakeet = activeDictationUsesParakeet
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Apple's preview keeps finalizing meanwhile, as the fallback if Parakeet fails.
            if usesParakeet, let text = await parakeetText(retainedAudio.snapshot()) {
                transcriber.stop()
                await finishDictation(rawText: text, recognitionError: nil)
                return
            }
            let rawText = await transcriber.waitForFinalization()
            await finishDictation(rawText: rawText, recognitionError: transcriber.error)
        }
    }

    /// Parakeet is chosen, downloaded, and knows the dictation's language.
    private func usesParakeet(for localeIdentifier: String) -> Bool {
        dictationEngine == .parakeet && parakeet.isDownloaded && parakeet.model.supports(localeIdentifier: localeIdentifier)
    }

    /// Recognizes a recording with Parakeet, then applies the vocabulary Apple Speech would get as
    /// hints. Nil when Parakeet fails or hears nothing, so the caller can fall back to Apple Speech.
    private func parakeetText(_ recorded: [AVAudioPCMBuffer]) async -> String? {
        let peakLevel = audio.peakLevel
        activeParakeetNeedsReview = ParakeetAutoInsertGate.requiresReview(peakLevel: peakLevel, confidence: nil)
        lastParakeetConfidence = nil
        lastParakeetPeakLevel = peakLevel
        guard !recorded.isEmpty else { return nil }
        do {
            let transcript = try await parakeet.transcribe(recorded)
            let model = parakeet.model.rawValue
            lastParakeetConfidence = transcript.confidence
            activeParakeetNeedsReview = ParakeetAutoInsertGate.requiresReview(
                peakLevel: peakLevel, confidence: transcript.confidence)
            parakeetLog.info("\(model, privacy: .public): \(transcript.processingSeconds, format: .fixed(precision: 3), privacy: .public) s for \(transcript.audioSeconds, format: .fixed(precision: 2), privacy: .public) s of audio, confidence \(transcript.confidence, format: .fixed(precision: 2), privacy: .public), peak \(peakLevel, format: .fixed(precision: 2), privacy: .public), auto-insert \(!self.activeParakeetNeedsReview, privacy: .public)")
            guard !transcript.text.isEmpty else { return nil }
            let vocabulary = lastDictationContextualStrings.filter { !Self.allModeHints.contains($0) }
            lastRecognitionUsedParakeet = true
            return DictationVocabularySnapper.apply(transcript.text, terms: vocabulary)
        } catch {
            parakeetLog.error("Parakeet failed, using Apple Speech: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Shared end of a live dictation and of a retry: process, save, then either type the
    /// text into the captured field or raise a notice the pill can recover from.
    private func finishDictation(rawText: String, recognitionError: String?) async {
        // What was recognized, and by which engine, so History can re-run it with the other one.
        let recordedForHistory = finishingAudioOverride ?? retainedAudio.snapshot()
        let recognizedBy: DictationEngine = lastRecognitionUsedParakeet ? .parakeet : .appleSpeech
        finishingAudioOverride = nil
        lastRecognitionUsedParakeet = false
        let isRetranscribing = retranscribingDictationID != nil
        rawDictationText = rawText
        // Phrases already typed live stay as typed; only what's left is cleaned up and typed now.
        let live = isRetranscribing ? nil : finishLiveTyping(rawText: rawText)
        var source = rawText
        if usesSmartCleanup, live == nil {
            // The rules first (they own spoken corrections), then the on-device model for what's left.
            let ruled = DictationLocalCleanup.removeFillers(
                from: activeDictationAppliesSpokenCorrections ? DictationBacktrack.apply(to: rawText) : rawText)
            if let polished = await DictationSmartCleanup.clean(ruled, session: smartCleanupSession) { source = polished }
        }
        smartCleanupSession = nil
        let processed = live?.text ?? DictationTranscriptProcessor.process(
            source, mode: activeDictationMode,
            snippets: activeDictationSnippets,
            applyCorrections: activeDictationAppliesSpokenCorrections,
            cleanupFillers: activeDictationCleansFillers,
            correctionRules: activeDictationCorrectionRules,
            tone: activeDictationTone)
        transcriber.replaceText(processed)
        if !processed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activeDictationProfileName = captureDictationProfileName
            activeDictationWritingStylePresetID = captureDictationWritingStylePresetID
            dictationResultGeneration += 1
        }
        saveCurrentDictation()
        let finished = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finished.isEmpty, let entryID = currentDictationHistoryEntryID, !recordedForHistory.isEmpty {
            holdHistoryAudio(recordedForHistory, for: entryID, engine: recognizedBy)
        }
        if isRetranscribing {
            // Re-running History audio never types anywhere or raises the pill's notices.
            retainedAudio.reset()
            showsFinishedTranscript = false
            dictationHistoryMessage = finished.isEmpty
                ? "\(recognizedBy.title) heard no words in this recording. The entry is unchanged."
                : "Re-transcribed with \(recognizedBy.title)."
        } else if let live {
            // Typed live: nothing is typed again, and Paste again stays off so nothing doubles.
            retainedAudio.reset()
            didInsertCurrentDictation = true
            if live.state != .active {
                showsFinishedTranscript = true
                if live.state == .stopped {
                    insertion.report("Typing stopped when the field lost focus. The rest is on the card.")
                }
            }
            insertion.logFocus("live finish state=\(live.state) card=\(showsFinishedTranscript)")
        } else if activeParakeetNeedsReview && !finished.isEmpty {
            dictationNotice = DictationRecovery.reviewBeforeInsertion(
                confidence: lastParakeetConfidence, peakLevel: lastParakeetPeakLevel ?? audio.peakLevel)
            showsFinishedTranscript = true
            retainedAudio.reset()
        } else if let notice = DictationRecovery.notice(audioError: nil, transcriberError: recognitionError,
                                                 transcript: processed, hasRetainedAudio: retainedAudio.isUsable,
                                                 heardSound: audio.peakLevel >= DictationRecovery.silenceLevel,
                                                 microphoneName: lastDictationMicrophoneName) {
            dictationNotice = notice
        } else {
            retainedAudio.reset()
            insertion.logFocus("finish hasTarget=\(dictationHasTarget)")
            if dictationHasTarget {
                await typeFinishedDictation(finished)
                // Typing didn't go through: keep the words on screen with Copy beside the notice.
                if !didInsertCurrentDictation, dictationNotice != nil { showsFinishedTranscript = true }
            } else if finishesWithoutTyping || (practiceKeepsDictationInApp && NSApp.isActive) {
                showsFinishedTranscript = false
            } else if !(await typeIntoFieldFocusedNow(finished)) {
                showsFinishedTranscript = true
            }
            insertion.logFocus("after inserted=\(didInsertCurrentDictation) card=\(showsFinishedTranscript) notice=\(dictationNotice != nil)")
        }
        if !finished.isEmpty, !isRetranscribing {
            recordUsage(raw: rawText, final: finished)
            completedDictationCount += 1
        }
        finishesWithoutTyping = false
        isFinalizingDictation = false
        captureGate.release(.dictation)
    }

    /// Types a finished dictation into the field it was started from, only if that field
    /// still has focus.
    private func typeFinishedDictation(_ text: String) async {
        guard insertion.isEnabled, !didInsertCurrentDictation else { return }
        if let target = capturedInsertionTarget {
            if insertion.insert(text, ifStillFocused: target) {
                didInsertCurrentDictation = true
                return
            }
            // The same field is still focused but refused direct typing: paste instead.
            // If focus moved, never paste somewhere else; offer Paste again.
            if insertion.focusState(of: target).fieldIsFocused,
               let app = dictationTargetApp, let pasteTarget = capturedPasteTarget {
                switch await insertion.paste(text, into: app, target: pasteTarget) {
                case .inserted, .unconfirmed:
                    didInsertCurrentDictation = true
                    return
                case .unavailable:
                    break
                }
            }
            // Unverified paste only into the field dictation started in, never one focus moved to.
            if insertion.focusState(of: target).fieldIsFocused, let app = dictationTargetApp,
               app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier {
                if await insertion.pasteDirectly(text, into: app) {
                    didInsertCurrentDictation = true
                    return
                }
            }
            if insertion.requiresReviewAfterInsertion {
                didInsertCurrentDictation = true
                return
            }
            dictationNotice = DictationRecovery.insertionFailed(
                insertion.status, canPasteAgain: capturedInsertionTarget != nil || capturedPasteTarget != nil)
        } else if let app = dictationTargetApp, let pasteTarget = capturedPasteTarget {
            switch await insertion.paste(text, into: app, target: pasteTarget) {
            case .inserted, .unconfirmed:
                didInsertCurrentDictation = true
                return
            case .unavailable:
                break
            }
            if app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier {
                if await insertion.pasteDirectly(text, into: app) {
                    didInsertCurrentDictation = true
                    return
                }
            }
            showsFinishedTranscript = true
        } else if let app = dictationTargetApp ?? NSWorkspace.shared.frontmostApplication,
                  app.bundleIdentifier != "com.ruddvz.hushkey" {
            if await insertion.pasteDirectly(text, into: app) {
                didInsertCurrentDictation = true
                return
            }
            showsFinishedTranscript = true
        } else {
            showsFinishedTranscript = true
        }
    }

    // MARK: - Live typing

    /// Starts typing settled phrases as they're heard, if the setting is on and the field allows it.
    /// Otherwise the dictation is typed at the end, as before.
    private func beginLiveTyping(usesParakeet: Bool) {
        endLiveTyping()
        let eligibility = LiveTypingEligibility.decide(
            enabled: typesWhileSpeaking,
            hasReadableField: insertion.isEnabled && capturedInsertionTarget != nil,
            isElectron: LiveTypingEligibility.isElectron(dictationTargetApp),
            usesParakeet: usesParakeet, mode: activeDictationMode)
        if typesWhileSpeaking {
            liveTypingLog.notice("live typing: \(String(describing: eligibility), privacy: .public)")
        }
        guard eligibility == .eligible else { return }
        liveTyping = LiveTypingSession()
        // A pause sends no new words, so the pause rule needs a clock of its own.
        liveTypingTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                self.advanceLiveTyping()
            }
        }
    }

    private func endLiveTyping() {
        liveTypingTimer?.cancel()
        liveTypingTimer = nil
        liveTyping = nil
    }

    private func liveTranscriptChanged(_ text: String) {
        guard var session = liveTyping, session.state == .active, liveTypingIsListening else { return }
        if let phrase = session.finalizer.update(transcript: text, at: session.elapsed()) {
            deliverLivePhrase(phrase, isLast: false, session: &session)
        }
        liveTyping = session
    }

    private func advanceLiveTyping() {
        guard var session = liveTyping, session.state == .active, liveTypingIsListening else { return }
        if let phrase = session.finalizer.advance(to: session.elapsed()) {
            deliverLivePhrase(phrase, isLast: false, session: &session)
        }
        liveTyping = session
    }

    /// Partials count only while the microphone is open; the rest is typed once at the end.
    private var liveTypingIsListening: Bool {
        #if LIVE_TYPING_REHEARSAL
        if isRehearsingLiveTyping { return true }
        #endif
        return audio.isRunning
    }

    #if LIVE_TYPING_REHEARSAL
    /// Developer check of live typing without a microphone, compiled only with
    /// `HUSHKEY_SWIFT_FLAGS="-D LIVE_TYPING_REHEARSAL" Scripts/package-app.sh`. Launch with
    /// `--args -liveTypingRehearsalApp <bundle id> -liveTypingRehearsal "words | more words"`: after 4 s,
    /// if that app is in front, it feeds the words one at a time, as Speech partials, into its focused field; "|" is a 1.5 s pause. The end
    /// works like a finished dictation, including the end-of-dictation insert when live typing is off.
    @ObservationIgnored private var isRehearsingLiveTyping = false

    private func rehearseLiveTypingIfRequested() {
        guard let script = UserDefaults.standard.string(forKey: "liveTypingRehearsal") else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            // Only into the app named with -liveTypingRehearsalApp <bundle id>, never whatever is in front.
            guard let self, let app = NSWorkspace.shared.frontmostApplication,
                  app.bundleIdentifier == UserDefaults.standard.string(forKey: "liveTypingRehearsalApp") else {
                self?.liveTypingLog.notice("rehearsal skipped: wrong app in front")
                return
            }
            insertion.logFocus("rehearsal start")
            capturedInsertionTarget = insertion.captureInsertionTarget()
            capturedPasteTarget = insertion.capturePasteTarget(into: app)
            dictationTargetApp = app
            capturedInsertionTargetName = capturedInsertionTarget?.applicationName
            dictationHasTarget = capturedInsertionTarget != nil || capturedPasteTarget != nil
            activeDictationMode = .natural
            activeDictationTone = .formal
            activeDictationCleansFillers = cleansDictationFillers
            activeDictationAppliesSpokenCorrections = appliesSpokenCorrections
            isRehearsingLiveTyping = true
            beginLiveTyping(usesParakeet: false)
            liveTypingLog.notice("rehearsal in \(app.localizedName ?? "?", privacy: .public): live=\(self.liveTyping != nil)")
            var heard = ""
            for token in script.split(separator: " ") {
                if token == "|" {
                    try? await Task.sleep(for: .seconds(1.5))
                    continue
                }
                heard = heard.isEmpty ? String(token) : heard + " " + token
                liveTranscriptChanged(heard)
                try? await Task.sleep(for: .milliseconds(300))
            }
            isRehearsingLiveTyping = false
            if let live = finishLiveTyping(rawText: heard) {
                liveTypingLog.notice("rehearsal live: \(String(describing: live.state), privacy: .public) \(live.text, privacy: .public)")
            } else {
                let text = DictationTranscriptProcessor.process(heard, mode: .natural, snippets: "",
                                                                cleanupFillers: cleansDictationFillers)
                // The same choice finishDictation makes.
                if dictationHasTarget { await typeFinishedDictation(text) }
                else { _ = await typeIntoFieldFocusedNow(text) }
                liveTypingLog.notice("rehearsal end insert: inserted=\(self.didInsertCurrentDictation) \(text, privacy: .public)")
            }
        }
    }
    #endif

    /// Ends live typing for a finished dictation and types what's left. Nil when nothing reached
    /// the field, so the dictation is typed the usual way and nothing is doubled.
    private func finishLiveTyping(rawText: String) -> LiveTypingSession? {
        guard var session = liveTyping else { return nil }
        endLiveTyping()
        guard session.hasDelivered else { return nil }
        let tail = session.finalizer.finish(transcript: rawText)
        deliverLivePhrase(tail, isLast: true, session: &session)
        liveTypingLog.notice("live typing finished: \(String(describing: session.state), privacy: .public)")
        return session
    }

    /// Cleans up one phrase and types it, only into the field dictation started in, and only while
    /// that field still has focus and reads back what was typed. Any failure stops live typing.
    private func deliverLivePhrase(_ phrase: LivePhraseFinalizer.Phrase, isLast: Bool,
                                   session: inout LiveTypingSession) {
        let text = processedLivePhrase(phrase, isLast: isLast)
        guard !text.isEmpty else { return }
        guard session.state == .active, let target = capturedInsertionTarget,
              insertion.insert(text, ifStillFocused: target) else {
            if session.state == .active {
                session.state = insertion.requiresReviewAfterInsertion ? .uncertain : .stopped
                let state = String(describing: session.state)
                liveTypingLog.notice("live typing stopped: \(state, privacy: .public)")
            }
            session.recordUntyped(text)
            return
        }
        session.recordTyped(text)
    }

    /// The same cleanup as a finished dictation, applied to one phrase. Casual tone drops a closing
    /// full stop only at the very end.
    private func processedLivePhrase(_ phrase: LivePhraseFinalizer.Phrase, isLast: Bool) -> String {
        var punctuation = phrase.leadingPunctuation
        if activeDictationTone == .veryCasual { punctuation = punctuation.replacingOccurrences(of: ".", with: "") }
        guard !phrase.words.isEmpty else { return punctuation }
        let tone: DictationTone = isLast || activeDictationTone != .casual ? activeDictationTone : .formal
        let processed = DictationTranscriptProcessor.process(
            phrase.words, mode: activeDictationMode, snippets: activeDictationSnippets,
            applyCorrections: activeDictationAppliesSpokenCorrections,
            cleanupFillers: activeDictationCleansFillers,
            correctionRules: activeDictationCorrectionRules, tone: tone)
        let text = LiveTypingSession.keepingLineBreaks(of: phrase.words, mode: activeDictationMode, in: processed)
        guard !punctuation.isEmpty, !text.isEmpty else { return punctuation + text }
        return punctuation + (text.first?.isWhitespace == true ? "" : " ") + text
    }

    /// No text field had focus when dictation began. If one has focus now, because the person
    /// clicked into it while talking, type there; otherwise the card stays up with Copy.
    private func typeIntoFieldFocusedNow(_ text: String) async -> Bool {
        guard insertion.isEnabled, !didInsertCurrentDictation, !text.isEmpty,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              app.bundleIdentifier != "com.ruddvz.hushkey" else { return false }
        capturedInsertionTarget = insertion.captureInsertionTarget()
        capturedInsertionTargetName = capturedInsertionTarget?.applicationName
        dictationTargetApp = app
        capturedPasteTarget = insertion.capturePasteTarget(into: app)
        if let target = capturedInsertionTarget, insertion.insert(text, ifStillFocused: target) {
            didInsertCurrentDictation = true
            return true
        }
        if let pasteTarget = capturedPasteTarget {
            switch await insertion.paste(text, into: app, target: pasteTarget) {
            case .inserted, .unconfirmed:
                didInsertCurrentDictation = true
                return true
            case .unavailable:
                break
            }
        }
        if await insertion.pasteDirectly(text, into: app) {
            didInsertCurrentDictation = true
            return true
        }
        return false
    }

    /// Runs recognition again over the failed dictation's audio, which was kept in memory.
    func retryDictation() async {
        guard dictationNotice?.canRetry == true, !audio.isRunning, !isFinalizingDictation,
              !transcriber.isRunning, !transcriber.isFinalizing else { return }
        let recorded = retainedAudio.snapshot()
        guard !recorded.isEmpty else {
            dismissDictationNotice()
            return
        }
        if dictationNotice?.kind == .cancelled { discardCancelledDictation() }
        guard captureGate.claim(.dictation) else {
            insertion.report("Meeting capture is active. Stop it before retrying dictation.")
            return
        }
        dictationNotice = nil
        isFinalizingDictation = true
        if activeDictationUsesParakeet, let text = await parakeetText(recorded) {
            await finishDictation(rawText: text, recognitionError: nil)
            return
        }
        let started = await transcriber.transcribe(recorded: recorded, localeIdentifier: activeDictationLanguageIdentifier,
                                                   contextualStrings: lastDictationContextualStrings)
        guard started else {
            isFinalizingDictation = false
            captureGate.release(.dictation)
            dictationNotice = DictationRecovery.notice(
                audioError: nil, transcriberError: transcriber.error ?? "Speech recognition did not start.",
                transcript: "", hasRetainedAudio: retainedAudio.isUsable)
            return
        }
        let rawText = await transcriber.waitForFinalization()
        await finishDictation(rawText: rawText, recognitionError: transcriber.error)
    }

    /// Types the last dictation again, only into the original app and field and only while
    /// they have focus. Otherwise it says where to click instead of guessing.
    func pasteLastDictationAgain() async {
        let text = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let focus = capturedInsertionTarget.map { insertion.focusState(of: $0) }
            ?? capturedPasteTarget.map { insertion.focusState(of: $0) }
            ?? (appIsFrontmost: false, fieldIsFocused: false)
        let decision = PasteAgainGate.decision(
            text: text, hasTarget: capturedInsertionTarget != nil || capturedPasteTarget != nil,
            isBusy: audio.isRunning || isFinalizingDictation || transcriber.isRunning || transcriber.isFinalizing,
            alreadyInserted: didInsertCurrentDictation, insertionEnabled: insertion.isEnabled,
            targetIsFrontmost: focus.appIsFrontmost, targetFieldIsFocused: focus.fieldIsFocused)
        switch decision {
        case .allowed:
            if let target = capturedInsertionTarget {
                if insertion.insert(text, ifStillFocused: target) {
                    didInsertCurrentDictation = true
                    dictationNotice = nil
                    completedDictationCount += 1
                    return
                }
                if insertion.requiresReviewAfterInsertion {
                    dictationNotice = DictationRecovery.pasteUnconfirmed(insertion.status, canPasteAgain: false)
                    return
                }
            }
            guard let app = dictationTargetApp, let pasteTarget = capturedPasteTarget else {
                dictationNotice = DictationRecovery.insertionFailed(insertion.status, canPasteAgain: true)
                return
            }
            switch await insertion.paste(text, into: app, target: pasteTarget) {
            case .inserted:
                didInsertCurrentDictation = true
                dictationNotice = nil
                completedDictationCount += 1
            case .unconfirmed:
                dictationNotice = DictationRecovery.pasteUnconfirmed(
                    insertion.status, canPasteAgain: true)
            case .unavailable:
                dictationNotice = DictationRecovery.insertionFailed(insertion.status, canPasteAgain: true)
            }
        case .focusLost:
            dictationNotice = DictationRecovery.focusLost(appName: capturedInsertionTarget?.applicationName ?? "the original app")
        case .unavailable(let reason):
            dictationNotice = DictationRecovery.insertionFailed(reason, canPasteAgain: false)
        }
    }

    func dismissFinishedTranscript() {
        showsFinishedTranscript = false
    }

    /// Hides the pill's notice and forgets any audio kept for a retry.
    func dismissDictationNotice() {
        dictationNotice = nil
        showsFinishedTranscript = false
        if !isFinalizingDictation { retainedAudio.reset() }
    }

    private func stopRetainingAudio(keep: Bool) {
        if let retainedAudioSinkID { audio.sink.remove(retainedAudioSinkID) }
        retainedAudioSinkID = nil
        if !keep { retainedAudio.reset() }
    }

    private func saveCurrentDictation() {
        let text = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DictationHistorySaveGate.shouldSave(text: text, lastSavedText: lastSavedDictationText,
                                                  enabled: savesDictationHistory) else { return }
        let raw = rawDictationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = DictationHistoryEntry(id: currentDictationHistoryEntryID ?? UUID(),
                                          text: text,
                                          rawText: raw.isEmpty || raw == text ? nil : raw,
                                          duration: lastDictationDuration,
                                          appName: activeDictationTarget)
        do {
            dictationHistory = try DictationHistoryStore.upsertingAndSaving(
                entry, to: dictationHistoryURL, existing: dictationHistory)
            currentDictationHistoryEntryID = entry.id
            lastSavedDictationText = text
            pruneDictationHistory()
            if dictationHistoryRecoveryCopyURL == nil { dictationHistoryMessage = nil }
        } catch {
            dictationHistoryMessage = "This transcript could not be saved to history: \(error.localizedDescription)"
        }
    }

    private static func archiveRecoveryMessage(_ name: String, copy: URL?) -> String {
        if let copy {
            return "Saved \(name.lowercased()) could not be read. HushKey kept a recovery copy at \(copy.path). Remove the unreadable archive to continue saving history."
        }
        return "Saved \(name.lowercased()) could not be read. HushKey left the original file in place but could not make a recovery copy. Remove the unreadable archive to continue saving history."
    }

    private func scheduleCurrentDictationSave() {
        cancelPendingDictationHistorySave()
        dictationHistorySaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.saveCurrentDictation()
            self.dictationHistorySaveTask = nil
        }
    }

    private func cancelPendingDictationHistorySave(flush: Bool = false) {
        let task = dictationHistorySaveTask
        dictationHistorySaveTask?.cancel()
        dictationHistorySaveTask = nil
        if flush, task != nil {
            saveCurrentDictation()
        }
    }

    private func clearLocalTransformUndo() {
        transformUndoOriginalText = nil
        transformUndoOutputText = nil
    }

    private func installDictationShortcut() {
        if let button = dictationShortcut.mouseButton {
            dictationHotKey.unregister()
            functionKey.uninstall()
            dictationMouseButton.install(button: button) { [weak self] pressed in
                guard let self else { return }
                switch self.dictationCaptureBehavior {
                case .hold:
                    if pressed { self.beginShortcutDictation() } else { self.endShortcutDictation() }
                case .toggle:
                    if pressed { Task { @MainActor in await self.toggleDictation() } }
                }
            }
            dictationShortcutStatus = dictationCaptureBehavior == .hold
                ? "Hold \(dictationShortcut.label) to dictate from any app; release to stop."
                : "Click \(dictationShortcut.label) to start or stop local dictation from any app."
            return
        }
        dictationMouseButton.uninstall()
        if dictationShortcut.usesFunctionKey {
            dictationHotKey.unregister()
            functionKey.onAction = { [weak self] action in self?.handleFunctionKey(action) }
            functionKey.install()
            functionKeyInstalledTrusted = AXIsProcessTrusted()
            refreshFunctionKeyStatus()
            return
        }
        functionKey.uninstall()
        let status: OSStatus
        switch dictationCaptureBehavior {
        case .hold:
            status = dictationHotKey.registerHold(keyCode: dictationShortcut.keyCode,
                                                  modifiers: dictationShortcut.carbonModifiers) { [weak self] pressed in
                guard let self else { return }
                if pressed { self.beginShortcutDictation() } else { self.endShortcutDictation() }
            }
        case .toggle:
            status = dictationHotKey.register(keyCode: dictationShortcut.keyCode,
                                              modifiers: dictationShortcut.carbonModifiers) { [weak self] in
                Task { @MainActor in await self?.toggleDictation() }
            }
        }
        dictationShortcutStatus = status == noErr
            ? dictationCaptureBehavior == .hold
                ? "Hold \(dictationShortcut.label) to dictate from any app; release to stop."
                : "Press \(dictationShortcut.label) to start or stop local dictation from any app."
            : "Could not register \(dictationShortcut.label) (system status \(status))."
    }

    private func installPasteLastShortcut() {
        pasteLastHotKey.unregister()
        pasteLastMouseButton.uninstall()
        guard let shortcut = pasteLastShortcut else {
            pasteLastShortcutStatus = "Off. The menu bar item still pastes the last transcript."
            return
        }
        if let button = shortcut.combo.mouseButton {
            pasteLastMouseButton.install(button: button) { [weak self] pressed in
                if pressed { Task { @MainActor in await self?.pasteLastDictationAgain() } }
            }
            pasteLastShortcutStatus = "Click \(shortcut.label) to paste your last transcript into the field it came from."
            return
        }
        let status = pasteLastHotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            Task { @MainActor in await self?.pasteLastDictationAgain() }
        }
        pasteLastShortcutStatus = status == noErr
            ? "Press \(shortcut.label) to paste your last transcript into the field it came from."
            : "Could not register \(shortcut.label) (system status \(status)). Another app may use it."
    }

    /// Settings is recording a new shortcut: let every key reach the recorder.
    func suspendShortcuts() {
        guard !shortcutsSuspended else { return }
        shortcutsSuspended = true
        dictationHotKey.unregister()
        functionKey.uninstall()
        dictationMouseButton.uninstall()
        selectedTextEditHotKey.unregister()
        pasteLastHotKey.unregister()
        pasteLastMouseButton.uninstall()
        insertion.suspendShortcuts()
    }

    func resumeShortcuts() {
        // The recorder finishing must not undo "Pause global shortcuts" from the menu.
        guard shortcutsSuspended, !shortcutsPausedByUser else { return }
        shortcutsSuspended = false
        guard started else { return }
        installDictationShortcut()
        installSelectedTextEditShortcut()
        installPasteLastShortcut()
        insertion.resumeShortcuts()
    }

    /// "Pause global shortcuts" in the menu: separate from the recorder's brief suspension.
    private(set) var shortcutsPausedByUser = false

    var isShortcutsPaused: Bool {
        get { shortcutsPausedByUser }
        set {
            guard newValue != shortcutsPausedByUser else { return }
            shortcutsPausedByUser = newValue
            if newValue { suspendShortcuts() } else { resumeShortcuts() }
        }
    }

    var canRecoverLastRecording: Bool {
        (!cancelledDictationAudio.isEmpty && cancelledDictation != nil) ||
        (dictationNotice?.canRetry == true && retainedAudio.isUsable)
    }

    func recoverLastRecording() async {
        if cancelledDictation != nil, !cancelledDictationAudio.isEmpty {
            await recoverCancelledDictation()
        } else if dictationNotice?.canRetry == true, retainedAudio.isUsable {
            await retryDictation()
        }
    }

    /// Deletes saved transcripts older than the retention setting, on this Mac only.
    func pruneDictationHistory(now: Date = Date()) {
        guard !dictationHistoryArchiveUnreadable else { return }
        let kept = dictationHistoryRetention.pruning(dictationHistory, now: now)
        guard kept.count != dictationHistory.count else { return }
        do {
            if kept.isEmpty { try DictationHistoryStore.delete(at: dictationHistoryURL) }
            else { try DictationHistoryStore.save(kept, to: dictationHistoryURL) }
            if let current = currentDictationHistoryEntryID, !kept.contains(where: { $0.id == current }) {
                currentDictationHistoryEntryID = nil
            }
            dictationHistory = kept
        } catch {
            dictationHistoryMessage = "Could not delete old transcripts: \(error.localizedDescription)"
        }
    }

    private func installSelectedTextEditShortcut() {
        let status = selectedTextEditHotKey.registerHold(
            keyCode: selectedTextEditShortcut.keyCode,
            modifiers: selectedTextEditShortcut.carbonModifiers) { [weak self] pressed in
                guard let self else { return }
                if pressed { self.beginSelectedTextEditShortcut() }
                else { self.endSelectedTextEditShortcut() }
            }
        selectedTextEditShortcutStatus = status == noErr
            ? "Hold \(selectedTextEditShortcut.label) with text selected to speak an edit instruction."
            : "Could not register \(selectedTextEditShortcut.label) (system status \(status))."
    }

    private func beginSelectedTextEditShortcut() {
        guard !selectedTextEditShortcutHeld, !audio.isRunning,
              !isFinalizingDictation, !isFinalizingSelectedTextEdit,
              !isApplyingSelectedTextEdit else { return }
        selectedTextEditShortcutHeld = true
        Task { @MainActor in
            await startSelectedTextEditCapture()
            if !selectedTextEditShortcutHeld, isSelectedTextEditCapturing {
                stopSelectedTextEditCapture()
            }
        }
    }

    private func endSelectedTextEditShortcut() {
        selectedTextEditShortcutHeld = false
        if isSelectedTextEditCapturing { stopSelectedTextEditCapture() }
    }

    private func startSelectedTextEditCapture() async {
        guard !audio.isRunning, !isFinalizingDictation,
              !isFinalizingSelectedTextEdit, !isApplyingSelectedTextEdit else { return }
        guard insertion.isEnabled else {
            selectedTextEditStatus = "Enable Accessibility text insertion in Settings before using voice edit."
            return
        }
        guard !meetingNotes.isStarting, !meetingNotes.isCapturing, !meetingNotes.isFinalizing,
              captureGate.claim(.dictation) else {
            selectedTextEditStatus = "Stop Meeting Notes before starting a voice edit."
            return
        }
        clearSelectedTextEdit()
        guard let selected = insertion.captureSelectedTextTarget() else {
            selectedTextEditStatus = "Select text in a supported, non-secure text field, then hold \(selectedTextEditShortcut.label)."
            captureGate.release(.dictation)
            return
        }

        selectedTextEditGeneration += 1
        let generation = selectedTextEditGeneration
        selectedTextEditTarget = selected.insertionTarget
        selectedTextEditTargetName = selected.insertionTarget.applicationName
        selectedTextEditOriginal = selected.selectedText
        selectedTextEditInstruction = ""
        selectedTextEditDraft = ""
        selectedTextEditApplied = false
        selectedTextEditStatus = "Starting secure on-device capture…"
        isStartingSelectedTextEdit = true
        selectedEditTranscriber.clear()
        defer { isStartingSelectedTextEdit = false }
        await audio.start()
        guard generation == selectedTextEditGeneration,
              selectedTextEditShortcutHeld, audio.isRunning else {
            audio.stop()
            clearSelectedTextEdit()
            selectedTextEditStatus = audio.error ?? "Voice edit capture did not start."
            captureGate.release(.dictation)
            return
        }

        let started = await selectedEditTranscriber.start(
            sink: audio.sink, localeIdentifier: dictationLanguage, contextualStrings: [])
        guard generation == selectedTextEditGeneration, audio.isRunning else {
            selectedEditTranscriber.stop()
            audio.stop()
            captureGate.release(.dictation)
            return
        }
        guard started else {
            let reason = selectedEditTranscriber.error ?? "On-device speech recognition could not start."
            audio.stop()
            captureGate.release(.dictation)
            clearSelectedTextEdit()
            selectedTextEditStatus = reason
            return
        }
        isSelectedTextEditCapturing = true
        selectedTextEditStatus = "Listening for your edit instruction. Release \(selectedTextEditShortcut.label) to finish; this instruction is not added to dictation history."
        if !selectedTextEditShortcutHeld { stopSelectedTextEditCapture() }
    }

    private func stopSelectedTextEditCapture() {
        guard isSelectedTextEditCapturing, audio.isRunning, !isFinalizingSelectedTextEdit else { return }
        selectedTextEditShortcutHeld = false
        isFinalizingSelectedTextEdit = true
        selectedEditTranscriber.beginFinalization()
        audio.stop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let instruction = await selectedEditTranscriber.waitForFinalization()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            selectedEditTranscriber.clear()
            isSelectedTextEditCapturing = false
            isFinalizingSelectedTextEdit = false
            captureGate.release(.dictation)
            selectedTextEditInstruction = instruction
            selectedTextEditDraft = ""
            selectedTextEditApplied = false
            screen = .transforms
            selectedTextEditStatus = instruction.isEmpty
                ? "No edit instruction was recognized. Your selected text is still unchanged; hold the shortcut to try again."
                : "Instruction ready. Create a local preview, review it, then Apply if it looks right."
        }
    }

    private func beginShortcutDictation() {
        guard !dictationShortcutHeld, !audio.isRunning else { return }
        dictationShortcutHeld = true
        Task { @MainActor in
            await startNewDictation()
            if !dictationShortcutHeld, audio.isRunning { stopDictation() }
        }
    }

    private func endShortcutDictation() {
        dictationShortcutHeld = false
        if isStartingDictation { stopWhileStarting() }
        else if audio.isRunning { stopDictation() }
    }

    /// Finish pressed before recognition was ready. If the microphone is already open or starting,
    /// the person may have spoken, so finish as soon as the start completes; otherwise nothing was heard.
    private func stopWhileStarting() {
        if audio.isRunning || audio.isStarting { stopsWhenStarted = true }
        else { cancelDictation() }
    }

    private func handleFunctionKey(_ action: FunctionKeyGesture.Action) {
        switch action {
        case .startHold: beginShortcutDictation()
        case .endHold: endShortcutDictation()
        case .abortHold: cancelDictation()
        case .startHandsFree:
            guard !audio.isRunning else { return }
            Task { @MainActor in await startNewDictation() }
        case .stopHandsFree:
            if isStartingDictation { stopWhileStarting() }
            else if audio.isRunning { stopDictation() }
        case .none, .scheduleHoldStart, .cancelHoldStart: break
        }
    }

    /// The fn key needs Accessibility access to be seen in other apps, and macOS must not use
    /// it for something else (emoji picker, input source, or Apple dictation).
    func refreshFunctionKeyStatus() {
        guard dictationShortcut.usesFunctionKey else { return }
        let trusted = AXIsProcessTrusted()
        if trusted, !functionKeyInstalledTrusted {
            // Monitors added before access was granted stay deaf, so add them again.
            functionKey.uninstall()
            functionKey.install()
            functionKeyInstalledTrusted = true
        }
        if !trusted {
            dictationShortcutStatus = "Could not watch the fn key yet. Allow HushKey in Accessibility settings."
        } else if let conflict = Self.globeKeyConflict {
            dictationShortcutStatus = "Set “Press 🌐 key to” to Do Nothing in Keyboard settings. It currently \(conflict)."
        } else {
            dictationShortcutStatus = "Hold fn to dictate from any app. Double-tap fn for hands-free; tap again to stop."
        }
    }

    /// What macOS does with the Globe key, when that would fight with dictation.
    static var globeKeyConflict: String? {
        switch UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int {
        case 1: "changes the input source"
        case 2: "shows emoji and symbols"
        case 3: "starts Apple dictation"
        default: nil
        }
    }

    /// Stops listening; nothing is transcribed, saved or inserted. With `offersUndo` (the pill's ×
    /// and Esc), a recording of a second or more stays in memory for a few seconds so the pill's
    /// Undo can transcribe it anyway; otherwise, or once that passes, the audio is dropped.
    func cancelDictation(offersUndo: Bool = false) {
        stopsWhenStarted = false
        let wasStarting = isStartingDictation
        let wasListening = audio.isRunning
        dictationShortcutHeld = false
        dictationStartGeneration += 1
        functionKey.reset()
        restoreOutputAfterDictation()
        // Phrases already typed stay in the field; nothing more is typed.
        endLiveTyping()
        guard wasStarting || wasListening else { return }
        transcriber.cancelPendingAuthorization()
        audio.stop()
        let recorded = dictationStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let keepsAudio = offersUndo && wasListening && recorded >= DictationRecovery.minimumUndoSeconds
        stopRetainingAudio(keep: keepsAudio)
        guard wasListening else {
            captureGate.release(.dictation)
            return
        }
        transcriber.stop()
        transcriber.clear()
        dictationStartedAt = nil
        captureGate.release(.dictation)
        guard keepsAudio, retainedAudio.isUsable else {
            retainedAudio.reset()
            return
        }
        lastDictationDuration = recorded
        cancelledDictationAudio = retainedAudio.snapshot()
        cancelledDictationSettings = currentRunSettings()
        cancelledDictation = CancelledDictation(cancelledAt: Date(), duration: recorded, appName: activeDictationTarget)
        dictationNotice = DictationRecovery.cancelled()
        cancelNoticeToken += 1
        let token = cancelNoticeToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            // With the pill on screen its countdown ring closes the notice, and waits while hovered.
            guard let self, !showsFloatingPill, token == cancelNoticeToken, dictationNotice?.kind == .cancelled else { return }
            dismissDictationNotice()
        }
    }

    /// Transcribes the last cancelled recording into History and the home composer. It is not
    /// typed anywhere: the field it was meant for has long lost focus.
    func recoverCancelledDictation() async {
        guard cancelledDictation != nil, !cancelledDictationAudio.isEmpty, let saved = cancelledDictationSettings,
              !audio.isRunning, !isStartingDictation, !isFinalizingDictation,
              !transcriber.isRunning, !transcriber.isFinalizing else { return }
        guard captureGate.claim(.dictation) else {
            insertion.report("Meeting capture is active. Stop it before recovering a dictation.")
            return
        }
        let recorded = cancelledDictationAudio
        let duration = cancelledDictation?.duration
        discardCancelledDictation()
        if dictationNotice?.kind == .cancelled { dictationNotice = nil }
        retainedAudio.reset()
        cancelPendingDictationHistorySave()
        saveCurrentDictation()
        lastSavedDictationText = nil
        currentDictationHistoryEntryID = nil
        transcriber.clear()
        rawDictationText = ""
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        capturedInsertionTarget = nil
        capturedPasteTarget = nil
        capturedInsertionTargetName = nil
        dictationTargetApp = nil
        dictationHasTarget = false
        apply(saved)
        lastDictationDuration = duration
        finishesWithoutTyping = true
        isFinalizingDictation = true
        finishingAudioOverride = recorded
        if activeDictationUsesParakeet, let text = await parakeetText(recorded) {
            await finishDictation(rawText: text, recognitionError: nil)
            return
        }
        let started = await transcriber.transcribe(recorded: recorded, localeIdentifier: activeDictationLanguageIdentifier,
                                                   contextualStrings: lastDictationContextualStrings)
        guard started else {
            finishesWithoutTyping = false
            finishingAudioOverride = nil
            isFinalizingDictation = false
            captureGate.release(.dictation)
            dictationNotice = DictationRecovery.notice(
                audioError: nil, transcriberError: transcriber.error ?? "Speech recognition did not start.",
                transcript: "", hasRetainedAudio: false)
            return
        }
        let rawText = await transcriber.waitForFinalization()
        await finishDictation(rawText: rawText, recognitionError: transcriber.error)
    }

    private func recordUsage(raw: String, final: String) {
        guard savesDictationHistory else { return }
        let words = final.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        usageLedger.record(words: words, seconds: lastDictationDuration,
                           wordsCleaned: UsageLedger.wordsCleaned(raw: raw, final: final), category: activeUsageCategory)
        try? UsageLedgerStore.save(usageLedger, to: usageLedgerURL)
    }

    /// Clears the Insights totals; History is left alone.
    func resetUsageInsights() {
        usageLedger = UsageLedger()
        try? UsageLedgerStore.save(usageLedger, to: usageLedgerURL)
    }

    /// Forgets the cancelled recording kept for History.
    func discardCancelledDictation() {
        cancelledDictation = nil
        cancelledDictationAudio = []
        cancelledDictationSettings = nil
    }

    /// Spoken command words Apple Speech is told to expect in each mode.
    static func modeHints(for mode: DictationMode) -> [String] {
        switch mode {
        case .message: ["DM", "FYI", "ASAP", "RSVP", "TL;DR"]
        case .email: ["subject", "greeting", "regards", "sincerely", "attachment", "forward"]
        case .code: ["underscore", "camelCase", "snake_case", "open parenthesis", "close parenthesis", "semicolon", "arrow"]
        case .automatic, .natural: []
        }
    }

    /// Not vocabulary: "camel case" must reach the code formatter as words, not as "camelCase".
    private static let allModeHints = Set(DictationMode.allCases.flatMap(modeHints(for:)))

    private func currentRunSettings() -> DictationRunSettings {
        DictationRunSettings(engine: activeDictationEngine, mode: activeDictationMode,
                             languageIdentifier: activeDictationLanguageIdentifier,
                             snippets: activeDictationSnippets, correctionRules: activeDictationCorrectionRules,
                             cleansFillers: activeDictationCleansFillers,
                             appliesSpokenCorrections: activeDictationAppliesSpokenCorrections,
                             usesSmartCleanup: activeDictationUsesSmartCleanup, tone: activeDictationTone,
                             contextualStrings: lastDictationContextualStrings,
                             profileName: captureDictationProfileName,
                             writingStylePresetID: captureDictationWritingStylePresetID,
                             usageCategory: activeUsageCategory)
    }

    private func apply(_ settings: DictationRunSettings) {
        activeDictationEngine = settings.engine
        activeDictationUsesParakeet = settings.engine == .parakeet &&
            parakeet.model.supports(localeIdentifier: settings.languageIdentifier) && parakeet.isDownloaded
        activeParakeetNeedsReview = false
        lastParakeetConfidence = nil
        lastParakeetPeakLevel = nil
        activeDictationMode = settings.mode
        activeDictationLanguageIdentifier = settings.languageIdentifier
        activeDictationSnippets = settings.snippets
        activeDictationCorrectionRules = settings.correctionRules
        activeDictationCleansFillers = settings.cleansFillers
        activeDictationAppliesSpokenCorrections = settings.appliesSpokenCorrections
        activeDictationUsesSmartCleanup = settings.usesSmartCleanup
        smartCleanupSession = settings.usesSmartCleanup ? DictationSmartCleanup.prepare() : nil
        activeDictationTone = settings.tone
        lastDictationContextualStrings = settings.contextualStrings
        captureDictationProfileName = settings.profileName
        captureDictationWritingStylePresetID = settings.writingStylePresetID
        activeUsageCategory = settings.usageCategory
    }

    private static func loadToneSettings() -> DictationToneSettings {
        let stored = UserDefaults.standard.dictionary(forKey: "dictationTones") as? [String: String] ?? [:]
        var settings = DictationToneSettings()
        for (context, tone) in stored {
            if let context = DictationContext(rawValue: context), let tone = DictationTone(rawValue: tone) {
                settings.tones[context] = tone
            }
        }
        return settings
    }

    /// Opens the Privacy & Security pane for a permission dictation needs.
    func openPrivacySettings(_ privacy: DictationNotice.Privacy) {
        guard let url = privacy.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the input tab of Sound settings, for a muted or missing microphone.
    func openSoundInputSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens the first-run tour again, bringing the window forward if it was closed.
    func openOnboarding() {
        showsOnboarding = true
        // An open hub shows the tour as a sheet; only open a window when there isn't one.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { openMainWindow?() }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Brings HushKey forward on Meeting notes, from the pill.
    func openMeetingNotes() {
        screen = .meetings
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether the hub window is on screen; set by the app delegate as windows open and close.
    @ObservationIgnored var isHubWindowOpen = false {
        didSet { if oldValue != isHubWindowOpen { applyDockVisibility() } }
    }

    func applyDockVisibility() {
        guard !AppDataDirectory.isRunningTests else { return }
        let policy = Self.activationPolicy(showsInDock: showsInDock, hubWindowOpen: isHubWindowOpen)
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Joining the Dock while the window is open: keep it in front rather than behind the last app.
        if policy == .regular, isHubWindowOpen { DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) } }
    }

    /// Menu bar first: a Dock icon only when asked for, or while the hub window is open so it can
    /// be found with ⌘-Tab. Closing the window drops back to the menu bar.
    nonisolated static func activationPolicy(showsInDock: Bool, hubWindowOpen: Bool) -> NSApplication.ActivationPolicy {
        showsInDock || hubWindowOpen ? .regular : .accessory
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginMessage = nil
        } catch {
            launchAtLoginMessage = "Couldn’t change the login item: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchesAtLogin = status == .enabled
        if status == .requiresApproval {
            launchAtLoginMessage = "Allow HushKey under Login Items in System Settings."
        }
    }

    /// A dictation app that isn't running can't hear fn, so HushKey starts at login unless you
    /// turn it off. Asked once; release builds only, so debug builds never register themselves.
    func enableLaunchAtLoginOnFirstRun() {
        #if !DEBUG
        let key = "didSetUpLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if SMAppService.mainApp.status != .enabled { setLaunchesAtLogin(true) }
        #endif
    }

    /// Quitting mid-dictation must not leave the Mac muted or drop a pending history save.
    func prepareForTermination() {
        cancelPendingDictationHistorySave(flush: true)
        cancelDictation(offersUndo: false)
        if isSelectedTextEditCapturing { stopSelectedTextEditCapture() }
        capture.cancel()
        audio.stop()
        recorder.stop()
        outputMuter.restore()
    }

    private func muteOutputForDictation() {
        guard mutesAudioWhileDictating else { return }
        // Let the start cue finish first.
        outputMuter.mute(after: playsDictationSounds ? DictationCue.start.duration + 0.05 : 0)
    }

    private func restoreOutputAfterDictation() {
        outputMuter.restore()
    }

    private func playDictationCue(_ cue: DictationCue) {
        guard playsDictationSounds else { return }
        cuePlayer.play(cue)
    }

}
