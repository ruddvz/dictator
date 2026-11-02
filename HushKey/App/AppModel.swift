import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

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
    let captureGate: AudioCaptureGate
    let meetingNotes: MeetingNotesService
    let localTransformService = LocalTransformService()
    let fileTranscriber = LocalFileTranscriber()
    let whisperFileTranscriber = WhisperKitFileTranscriber()
    let fileTranscriptionWorkspace = FileTranscriptionWorkspace()
    let insertion = TextInsertionService()
    let capture = CaptureController()
    let recorder = SessionRecorder()

    var screen: Screen = .dictation {
        didSet {
            syncCaptureMode()
            updateMotionActivity()
        }
    }

    // MARK: Training

    private(set) var dataset = TemplateStore.load()
    var selectedWord: String?
    var featureSet: FeatureSet = .all {
        didSet { rebuildClassifier() }
    }
    private(set) var classifier: TemplateClassifier?
    private(set) var evaluation: Evaluation?
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
            if started { installDictationShortcut() }
        }
    }
    var selectedTextEditShortcut: SelectedTextEditShortcut = SelectedTextEditShortcut(
        rawValue: UserDefaults.standard.string(forKey: SelectedTextEditShortcut.preferenceKey) ?? "") ?? .default {
        didSet {
            UserDefaults.standard.set(selectedTextEditShortcut.rawValue, forKey: SelectedTextEditShortcut.preferenceKey)
            if started { installSelectedTextEditShortcut() }
        }
    }
    var dictationCaptureBehavior: DictationCaptureBehavior = DictationCaptureBehavior(
        rawValue: UserDefaults.standard.string(forKey: DictationCaptureBehavior.preferenceKey) ?? "") ?? .hold {
        didSet {
            UserDefaults.standard.set(dictationCaptureBehavior.rawValue, forKey: DictationCaptureBehavior.preferenceKey)
            if started { installDictationShortcut() }
        }
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
    var appliesSpokenCorrections = UserDefaults.standard.object(forKey: "applySpokenCorrections") as? Bool ?? true {
        didSet { UserDefaults.standard.set(appliesSpokenCorrections, forKey: "applySpokenCorrections") }
    }
    var cleansDictationFillers = UserDefaults.standard.object(forKey: "cleanDictationFillers") as? Bool ?? false {
        didSet { UserDefaults.standard.set(cleansDictationFillers, forKey: "cleanDictationFillers") }
    }
    var showsFloatingPill = UserDefaults.standard.object(forKey: "showFloatingPill") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsFloatingPill, forKey: "showFloatingPill") }
    }
    /// Tone per context (Personal messages, Work messages, Email, Other); see the Style page.
    var dictationToneSettings = AppModel.loadToneSettings() {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: dictationToneSettings.tones.map { ($0.key.rawValue, $0.value.rawValue) })
            UserDefaults.standard.set(stored, forKey: "dictationTones")
        }
    }
    /// A soft system sound when dictation starts listening and when it stops. Off by default.
    var playsDictationSounds = UserDefaults.standard.bool(forKey: "playDictationSounds") {
        didSet { UserDefaults.standard.set(playsDictationSounds, forKey: "playDictationSounds") }
    }
    var savesDictationHistory = UserDefaults.standard.object(forKey: "saveDictationHistory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(savesDictationHistory, forKey: "saveDictationHistory") }
    }
    private(set) var dictationHistory: [DictationHistoryEntry]
    private(set) var didInsertCurrentDictation = false
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
    private(set) var isSelectedTextEditCapturing = false
    private(set) var isFinalizingSelectedTextEdit = false
    private(set) var isGeneratingSelectedTextEdit = false
    private(set) var isApplyingSelectedTextEdit = false
    private(set) var selectedTextEditApplied = false
    private(set) var usedNearbyTextHints = false
    private(set) var isFinalizingDictation = false
    /// The pill's error state for the last dictation, with the recoveries it allows.
    private(set) var dictationNotice: DictationNotice?
    /// Bumped each time a dictation ends with text, so the pill can flash its done state.
    private(set) var completedDictationCount = 0
    private(set) var dictationResultGeneration = 0
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
    @ObservationIgnored private var capturedPasteTarget: TextInsertionService.PasteTarget?
    @ObservationIgnored private var selectedTextEditTarget: TextInsertionService.InsertionTarget?
    @ObservationIgnored private let selectedEditTranscriber = MicTranscriber()
    @ObservationIgnored private let retainedAudio = RetainedDictationAudio()
    @ObservationIgnored private var retainedAudioSinkID: UUID?
    @ObservationIgnored private var lastDictationContextualStrings: [String] = []
    @ObservationIgnored private var activeDictationLanguageIdentifier = "en-US"
    @ObservationIgnored private var activeDictationSnippets = ""
    @ObservationIgnored private var activeDictationCorrectionRules = ""
    @ObservationIgnored private var activeDictationCleansFillers = false
    @ObservationIgnored private var captureDictationProfileName: String?
    @ObservationIgnored private var captureDictationWritingStylePresetID: UUID?

    // MARK: Decoding

    var useCaptureMode: CaptureController.Mode = .hold {
        didSet { syncCaptureMode() }
    }
    var maxDistance: Double = 1.5
    var minConfidence: Double = 0.05
    private(set) var decoded: [DecodedWord] = []
    private(set) var lastSegment: [MotionSample] = []
    private(set) var lastInsertedPredictionID: UUID?

    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private let dictationHotKey = GlobalHotKeyRegistration(id: 2)
    @ObservationIgnored private let functionKey = FunctionKeyMonitor()
    @ObservationIgnored private var functionKeyInstalledTrusted = false
    @ObservationIgnored private let selectedTextEditHotKey = GlobalHotKeyRegistration(id: 4)
    @ObservationIgnored private var started = false
    @ObservationIgnored private var motionStarted = false
    /// The dictation key is held down (hold to talk). Observed so the pill can drop its buttons.
    private(set) var dictationShortcutHeld = false
    @ObservationIgnored private var selectedTextEditShortcutHeld = false
    @ObservationIgnored private var dictationStartGeneration = 0
    @ObservationIgnored private var selectedTextEditGeneration = 0

    init(dictationHistoryURL: URL = DictationHistoryStore.url,
         fileTranscriptionHistoryURL: URL = FileTranscriptionSessionStore.url) {
        self.dictationHistoryURL = dictationHistoryURL
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
        capture.onSegment = { [weak self] segment in self?.handleSegment(segment) }
        audio.refreshDevices()
        installKeyMonitor()
        installDictationShortcut()
        installSelectedTextEditShortcut()
        updateMotionActivity()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFunctionKeyStatus() }
        }
    }

    private func ingest(_ sample: MotionSample) {
        capture.ingest(sample)
        recorder.record(sample)
    }

    private func syncCaptureMode() {
        capture.autoEnabled = isMotionInferenceEnabled && screen == .use && useCaptureMode == .auto
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
                addTemplate(Template(label: word, samples: segment,
                                     condition: trainingCondition, sessionID: experimentSessionID))
                recorder.logEvent(segment, kind: "train", label: word, confidence: nil)
            } else if recorder.isRecording {
                recorder.logEvent(segment, kind: "segment", label: recorder.prompt, confidence: nil)
            }
        case .use:
            guard isMotionInferenceEnabled, let classifier else {
                recorder.logEvent(segment, kind: "blocked-no-evidence", label: "", confidence: nil)
                return
            }
            let prediction = classifier.predict(segment, maxDistance: maxDistance, minConfidence: minConfidence)
            lastInsertedPredictionID = nil
            decoded.append(DecodedWord(prediction: prediction))
            recorder.logEvent(segment, kind: prediction.accepted ? "decode" : "reject",
                              label: prediction.best?.label ?? "", confidence: prediction.confidence)
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

    func templateCount(for word: String, condition: SessionRecorder.Condition) -> Int {
        templates(for: word, condition: condition).count
    }

    func beginNewExperimentSession() {
        experimentSessionID = UUID()
        dataMessage = "New session started. These takes can be held out from earlier sessions."
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

    func addTemplate(_ template: Template) {
        dataset.templates.append(template)
        lastTemplateID = template.id
        persist()
    }

    func clearTrainingData() {
        dataset.templates.removeAll()
        lastTemplateID = nil
        persist()
        dataMessage = "Training templates deleted from this Mac."
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
            dataMessage = "Session logs and local audio files deleted."
        } catch {
            dataMessage = "Session deletion failed: \(error.localizedDescription)"
        }
    }

    func deleteTemplate(_ id: Template.ID) {
        dataset.templates.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        TemplateStore.save(dataset)
        rebuildClassifier()
    }

    private func rebuildClassifier() {
        let silentTemplates = dataset.templates.filter { ($0.condition ?? .silent) == .silent }
        classifier = TemplateClassifier(templates: silentTemplates, featureSet: featureSet)
        evaluation = nil
        syncCaptureMode()
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
            self.isEvaluating = false
            self.syncCaptureMode()
        }
    }

    var templatesForSelectedCondition: [Template] {
        return dataset.templates.filter { ($0.condition ?? .silent) == trainingCondition }
    }

    // MARK: Decode transcript

    var transcript: String {
        decoded.filter(\.prediction.accepted).map(\.text).joined(separator: " ")
    }

    var isMotionInferenceEnabled: Bool {
        guard trainingCondition == .silent,
              let evaluation,
              let holdout = evaluation.sessionHoldoutAccuracy,
              let holdoutBaseline = evaluation.sessionHoldoutChance else { return false }
        return evaluation.templateCount >= 50 &&
            evaluation.accuracy > evaluation.chance &&
            evaluation.pValue < 0.05 &&
            holdout > holdoutBaseline
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
        if insertion.insert(text) {
            didInsertCurrentDictation = true
            dictationNotice = nil
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

    func deleteDictation(_ entry: DictationHistoryEntry) {
        let remaining = dictationHistory.filter { $0.id != entry.id }
        do {
            if remaining.isEmpty { try DictationHistoryStore.delete(at: dictationHistoryURL) }
            else { try DictationHistoryStore.save(remaining, to: dictationHistoryURL) }
            dictationHistory = remaining
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
        screen = .dictation
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
            cancelDictation()
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
        defer { isStartingDictation = false }
        dictationStartGeneration += 1
        let generation = dictationStartGeneration
        dictationNotice = nil
        showsFinishedTranscript = false
        retainedAudio.reset()
        let target = NSWorkspace.shared.frontmostApplication
        let isHushKey = target?.bundleIdentifier == "com.ruddvz.hushkey"
        activeDictationTarget = isHushKey ? nil : target?.localizedName
        capturedInsertionTarget = isHushKey ? nil : insertion.captureInsertionTarget()
        capturedPasteTarget = nil
        if !isHushKey, let target {
            capturedPasteTarget = insertion.capturePasteTarget(into: target)
        }
        capturedInsertionTargetName = capturedInsertionTarget?.applicationName
        dictationTargetApp = isHushKey ? nil : target
        dictationHasTarget = insertion.isEnabled && (capturedInsertionTarget != nil || capturedPasteTarget != nil)
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
        captureDictationProfileName = profileSettings.appName
        captureDictationWritingStylePresetID = profileSettings.writingStylePresetID
        let nearbyHints = usesNearbyTextHints ? insertion.nearbyContextHints() : []
        usedNearbyTextHints = !nearbyHints.isEmpty

        let speechReady = await transcriber.prepare(localeIdentifier: activeDictationLanguageIdentifier)
        guard generation == dictationStartGeneration else {
            captureGate.release(.dictation)
            return
        }
        guard speechReady else {
            captureGate.release(.dictation)
            dictationNotice = DictationRecovery.notice(
                audioError: nil, transcriberError: transcriber.error ?? "Local speech recognition is unavailable.",
                transcript: "", hasRetainedAudio: false)
            return
        }

        await audio.start()
        guard generation == dictationStartGeneration, audio.isRunning else {
            audio.stop()
            captureGate.release(.dictation)
            if generation == dictationStartGeneration {
                dictationNotice = DictationRecovery.notice(audioError: audio.error ?? "The microphone did not start.",
                                                           transcriberError: nil, transcript: "", hasRetainedAudio: false)
            }
            return
        }
        retainedAudioSinkID = audio.sink.add { [retainedAudio] buffer, _ in retainedAudio.append(buffer) }
        lastDictationMicrophoneName = audio.activeDeviceName
        playDictationSound("Tink")
        dictationStartedAt = Date()
        lastDictationDuration = nil
        let customWords = profileSettings.vocabulary
        let modeHints: [String]
        switch activeDictationMode {
        case .message: modeHints = ["DM", "FYI", "ASAP", "RSVP", "TL;DR"]
        case .email: modeHints = ["subject", "greeting", "regards", "sincerely", "attachment", "forward"]
        case .code: modeHints = ["underscore", "camelCase", "snake_case", "open parenthesis", "close parenthesis", "semicolon", "arrow"]
        case .automatic, .natural: modeHints = []
        }
        lastDictationContextualStrings = DictationContextHints.prioritized(customWords: customWords,
                                                                           modeHints: modeHints,
                                                                           nearbyHints: nearbyHints,
                                                                           learnedWords: dataset.vocabulary)
        let started = await transcriber.start(sink: audio.sink, localeIdentifier: activeDictationLanguageIdentifier,
                                              contextualStrings: lastDictationContextualStrings)
        guard generation == dictationStartGeneration, audio.isRunning else {
            transcriber.stop()
            audio.stop()
            stopRetainingAudio(keep: false)
            captureGate.release(.dictation)
            return
        }
        if !started {
            audio.stop()
            stopRetainingAudio(keep: false)
            captureGate.release(.dictation)
            dictationNotice = DictationRecovery.notice(
                audioError: nil, transcriberError: transcriber.error ?? "Speech recognition did not start.",
                transcript: "", hasRetainedAudio: false)
        }
    }

    private func stopDictation() {
        guard audio.isRunning else { return }
        dictationStartGeneration += 1
        isFinalizingDictation = true
        if transcriber.isRunning { transcriber.beginFinalization() }
        else { transcriber.stop() }
        audio.stop()
        stopRetainingAudio(keep: true)
        playDictationSound("Pop")
        functionKey.reset()
        lastDictationDuration = dictationStartedAt.map { Date().timeIntervalSince($0) }
        dictationStartedAt = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            let rawText = await transcriber.waitForFinalization()
            await finishDictation(rawText: rawText)
        }
    }

    /// Shared end of a live dictation and of a retry: process, save, then either type the
    /// text into the captured field or raise a notice the pill can recover from.
    private func finishDictation(rawText: String) async {
        rawDictationText = rawText
        let processed = DictationTranscriptProcessor.process(rawText, mode: activeDictationMode,
                                                              snippets: activeDictationSnippets,
                                                              applyCorrections: appliesSpokenCorrections,
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
        if let notice = DictationRecovery.notice(audioError: nil, transcriberError: transcriber.error,
                                                 transcript: processed, hasRetainedAudio: retainedAudio.isUsable,
                                                 heardSound: audio.peakLevel >= DictationRecovery.silenceLevel,
                                                 microphoneName: lastDictationMicrophoneName) {
            dictationNotice = notice
        } else {
            retainedAudio.reset()
            let finished = processed.trimmingCharacters(in: .whitespacesAndNewlines)
            recordUsage(raw: rawText, final: finished)
            if dictationHasTarget {
                await typeFinishedDictation(finished)
            } else if finishesWithoutTyping {
                showsFinishedTranscript = false
            } else if !typeIntoFieldFocusedNow(finished) {
                showsFinishedTranscript = true
            }
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
                case .inserted:
                    didInsertCurrentDictation = true
                    return
                case .unconfirmed:
                    dictationNotice = DictationRecovery.pasteUnconfirmed(
                        insertion.status, canPasteAgain: capturedPasteTarget != nil)
                    return
                case .unavailable:
                    break
                }
            }
            dictationNotice = DictationRecovery.insertionFailed(
                insertion.status, canPasteAgain: capturedInsertionTarget != nil || capturedPasteTarget != nil)
        } else if let app = dictationTargetApp, let pasteTarget = capturedPasteTarget {
            switch await insertion.paste(text, into: app, target: pasteTarget) {
            case .inserted:
                didInsertCurrentDictation = true
            case .unconfirmed:
                dictationNotice = DictationRecovery.pasteUnconfirmed(
                    insertion.status, canPasteAgain: capturedPasteTarget != nil)
            case .unavailable:
                showsFinishedTranscript = true
            }
        } else {
            showsFinishedTranscript = true
        }
    }

    /// No text field had focus when dictation began. If one has focus now, because the person
    /// clicked into it while talking, type there; otherwise the card stays up with Copy.
    private func typeIntoFieldFocusedNow(_ text: String) -> Bool {
        guard insertion.isEnabled, !didInsertCurrentDictation, !text.isEmpty,
              let target = insertion.captureInsertionTarget(),
              insertion.insert(text, ifStillFocused: target) else { return false }
        capturedInsertionTarget = target
        capturedInsertionTargetName = target.applicationName
        didInsertCurrentDictation = true
        return true
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
        await finishDictation(rawText: rawText)
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
            if let target = capturedInsertionTarget, insertion.insert(text, ifStillFocused: target) {
                didInsertCurrentDictation = true
                dictationNotice = nil
                completedDictationCount += 1
                return
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
                                          duration: lastDictationDuration)
        do {
            dictationHistory = try DictationHistoryStore.upsertingAndSaving(
                entry, to: dictationHistoryURL, existing: dictationHistory)
            currentDictationHistoryEntryID = entry.id
            lastSavedDictationText = text
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

    private func cancelPendingDictationHistorySave() {
        dictationHistorySaveTask?.cancel()
        dictationHistorySaveTask = nil
    }

    private func clearLocalTransformUndo() {
        transformUndoOriginalText = nil
        transformUndoOutputText = nil
    }

    private func installDictationShortcut() {
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
        if audio.isRunning { stopDictation() }
        else if isStartingDictation { cancelDictation() }
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
            if audio.isRunning { stopDictation() }
            else if isStartingDictation { cancelDictation() }
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
        let wasStarting = isStartingDictation
        let wasListening = audio.isRunning
        dictationShortcutHeld = false
        dictationStartGeneration += 1
        functionKey.reset()
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
            guard let self, token == cancelNoticeToken, dictationNotice?.kind == .cancelled else { return }
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
        let started = await transcriber.transcribe(recorded: recorded, localeIdentifier: activeDictationLanguageIdentifier,
                                                   contextualStrings: lastDictationContextualStrings)
        guard started else {
            finishesWithoutTyping = false
            isFinalizingDictation = false
            captureGate.release(.dictation)
            dictationNotice = DictationRecovery.notice(
                audioError: nil, transcriberError: transcriber.error ?? "Speech recognition did not start.",
                transcript: "", hasRetainedAudio: false)
            return
        }
        let rawText = await transcriber.waitForFinalization()
        await finishDictation(rawText: rawText)
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

    private func currentRunSettings() -> DictationRunSettings {
        DictationRunSettings(mode: activeDictationMode, languageIdentifier: activeDictationLanguageIdentifier,
                             snippets: activeDictationSnippets, correctionRules: activeDictationCorrectionRules,
                             cleansFillers: activeDictationCleansFillers, tone: activeDictationTone,
                             contextualStrings: lastDictationContextualStrings,
                             profileName: captureDictationProfileName,
                             writingStylePresetID: captureDictationWritingStylePresetID,
                             usageCategory: activeUsageCategory)
    }

    private func apply(_ settings: DictationRunSettings) {
        activeDictationMode = settings.mode
        activeDictationLanguageIdentifier = settings.languageIdentifier
        activeDictationSnippets = settings.snippets
        activeDictationCorrectionRules = settings.correctionRules
        activeDictationCleansFillers = settings.cleansFillers
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

    /// Opens the input tab of Sound settings, for a muted or missing microphone.
    func openSoundInputSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Brings HushKey forward on Meeting notes, from the pill.
    func openMeetingNotes() {
        screen = .meetings
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func playDictationSound(_ name: String) {
        guard playsDictationSounds, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.35
        sound.play()
    }

}
