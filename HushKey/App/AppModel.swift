import AppKit
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
        case settings = "Settings & Data"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .dictation: "mic"
            case .transforms: "wand.and.stars"
            case .files: "waveform.badge.mic"
            case .meetings: "person.2.wave.2"
            case .setup: "headphones"
            case .train: "square.stack.3d.up"
            case .evaluate: "chart.bar.xaxis"
            case .use: "text.bubble"
            case .personalization: "text.badge.plus"
            case .settings: "slider.horizontal.3"
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
    private(set) var fileTranscriptionSessions = FileTranscriptionSessionStore.load()
    private(set) var fileTranscriptionHistoryMessage: String?

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
    private(set) var isSelectedTextEditCapturing = false
    private(set) var isFinalizingSelectedTextEdit = false
    private(set) var isGeneratingSelectedTextEdit = false
    private(set) var isApplyingSelectedTextEdit = false
    private(set) var selectedTextEditApplied = false
    private(set) var usedNearbyTextHints = false
    private(set) var isFinalizingDictation = false
    @ObservationIgnored private(set) var lastSavedDictationText: String?
    @ObservationIgnored private let dictationHistoryURL: URL
    @ObservationIgnored private var dictationHistorySaveTask: Task<Void, Never>?
    @ObservationIgnored private var currentDictationHistoryEntryID: UUID?
    @ObservationIgnored private var capturedInsertionTarget: TextInsertionService.InsertionTarget?
    @ObservationIgnored private var selectedTextEditTarget: TextInsertionService.InsertionTarget?
    @ObservationIgnored private let selectedEditTranscriber = MicTranscriber()

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
    @ObservationIgnored private let selectedTextEditHotKey = GlobalHotKeyRegistration(id: 4)
    @ObservationIgnored private var started = false
    @ObservationIgnored private var motionStarted = false
    @ObservationIgnored private var dictationShortcutHeld = false
    @ObservationIgnored private var selectedTextEditShortcutHeld = false
    @ObservationIgnored private var dictationStartGeneration = 0
    @ObservationIgnored private var selectedTextEditGeneration = 0

    init(dictationHistoryURL: URL = DictationHistoryStore.url) {
        self.dictationHistoryURL = dictationHistoryURL
        dictationHistory = DictationHistoryStore.load(from: dictationHistoryURL) ?? []
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

    func saveFileTranscriptionSession(_ session: FileTranscriptionSession) {
        let updated = FileTranscriptionSessionStore.upserting(session, into: fileTranscriptionSessions)
        do {
            try FileTranscriptionSessionStore.save(updated)
            fileTranscriptionSessions = updated
            fileTranscriptionHistoryMessage = nil
        } catch {
            fileTranscriptionHistoryMessage = "Couldn’t save this transcript locally: \(error.localizedDescription)"
        }
    }

    func deleteFileTranscriptionSession(_ session: FileTranscriptionSession) {
        let updated = FileTranscriptionSessionStore.deleting(id: session.id, from: fileTranscriptionSessions)
        do {
            try FileTranscriptionSessionStore.save(updated)
            fileTranscriptionSessions = updated
            fileTranscriptionHistoryMessage = nil
        } catch {
            fileTranscriptionHistoryMessage = "Couldn’t delete this transcript: \(error.localizedDescription)"
        }
    }

    func clearFileTranscriptionHistory() {
        do {
            try FileTranscriptionSessionStore.deleteAll()
            fileTranscriptionSessions.removeAll()
            fileTranscriptionHistoryMessage = nil
        } catch {
            fileTranscriptionHistoryMessage = "Couldn’t delete saved transcripts: \(error.localizedDescription)"
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
        case .dictation, .transforms, .files, .meetings, .setup, .evaluate, .personalization:
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
        if insertion.insert(text) { didInsertCurrentDictation = true }
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
        let draft = selectedTextEditDraft.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if await insertion.insert(text, into: target) { didInsertCurrentDictation = true }
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
        if isStartingSelectedTextEdit {
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
        do {
            try DictationHistoryStore.delete(at: dictationHistoryURL)
            cancelPendingDictationHistorySave()
            dictationHistory.removeAll()
            currentDictationHistoryEntryID = nil
            lastSavedDictationText = nil
            dictationHistoryMessage = "Saved transcript history was deleted from this Mac."
        } catch {
            dictationHistoryMessage = "Could not delete transcript history: \(error.localizedDescription)"
            return
        }
        if !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing {
            transcriber.clear()
            capturedInsertionTarget = nil
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
        capturedInsertionTargetName = nil
        rawDictationText = entry.rawText ?? entry.text
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        lastSavedDictationText = restoredText
        currentDictationHistoryEntryID = nil
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
        capturedInsertionTargetName = nil
        rawDictationText = ""
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        lastSavedDictationText = nil
        currentDictationHistoryEntryID = nil
    }

    func requestNearbyTextAccess() {
        _ = insertion.requestAccessibilityAccessForContext()
    }

    @discardableResult
    func saveDictationAppProfile(appName: String, bundleIdentifier: String, mode: DictationMode,
                                 vocabulary: String) -> Bool {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80,
              DictationAppProfile.isValidBundleIdentifier(identifier),
              mode != .automatic, vocabulary.utf8.count <= 4_000 else { return false }
        let profile = DictationAppProfile(appName: name, bundleIdentifier: identifier,
                                          mode: mode, vocabulary: vocabulary)
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
        dictationStartGeneration += 1
        let generation = dictationStartGeneration
        let target = NSWorkspace.shared.frontmostApplication
        let isHushKey = target?.bundleIdentifier == "com.ruddvz.hushkey"
        activeDictationTarget = isHushKey ? nil : target?.localizedName
        capturedInsertionTarget = isHushKey ? nil : insertion.captureInsertionTarget()
        capturedInsertionTargetName = capturedInsertionTarget?.applicationName
        let targetBundleIdentifier = isHushKey ? nil : target?.bundleIdentifier
        let activeProfile = DictationAppProfile.profile(for: targetBundleIdentifier, in: dictationAppProfiles)
        activeDictationProfileName = activeProfile?.appName
        activeDictationMode = DictationAppProfile.resolvedMode(requested: dictationMode,
                                                                bundleIdentifier: targetBundleIdentifier,
                                                                profiles: dictationAppProfiles)
        let nearbyHints = usesNearbyTextHints ? insertion.nearbyContextHints() : []
        usedNearbyTextHints = !nearbyHints.isEmpty

        await audio.start()
        guard generation == dictationStartGeneration, audio.isRunning else {
            audio.stop()
            captureGate.release(.dictation)
            return
        }
        let customWords = DictationVocabulary.terms(from: dictationTerms) +
            DictationAppProfile.vocabulary(for: targetBundleIdentifier, in: dictationAppProfiles)
        let modeHints: [String]
        switch activeDictationMode {
        case .message: modeHints = ["DM", "FYI", "ASAP", "RSVP", "TL;DR"]
        case .email: modeHints = ["subject", "greeting", "regards", "sincerely", "attachment", "forward"]
        case .code: modeHints = ["underscore", "camelCase", "snake_case", "open parenthesis", "close parenthesis", "semicolon", "arrow"]
        case .automatic, .natural: modeHints = []
        }
        let started = await transcriber.start(sink: audio.sink, localeIdentifier: dictationLanguage,
                                              contextualStrings: DictationContextHints.prioritized(
                                                customWords: customWords,
                                                modeHints: modeHints,
                                                nearbyHints: nearbyHints,
                                                learnedWords: dataset.vocabulary))
        guard generation == dictationStartGeneration, audio.isRunning else {
            transcriber.stop()
            audio.stop()
            captureGate.release(.dictation)
            return
        }
        if !started {
            audio.stop()
            captureGate.release(.dictation)
        }
    }

    private func stopDictation() {
        guard audio.isRunning else { return }
        dictationStartGeneration += 1
        isFinalizingDictation = true
        if transcriber.isRunning { transcriber.beginFinalization() }
        else { transcriber.stop() }
        audio.stop()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let rawText = await transcriber.waitForFinalization()
            rawDictationText = rawText
            let processed = DictationTranscriptProcessor.process(rawText, mode: activeDictationMode,
                                                                  snippets: dictationSnippets,
                                                                  applyCorrections: appliesSpokenCorrections,
                                                                  cleanupFillers: cleansDictationFillers,
                                                                  correctionRules: dictationCorrectionRules)
            transcriber.replaceText(processed)
            saveCurrentDictation()
            isFinalizingDictation = false
            captureGate.release(.dictation)
        }
    }

    private func saveCurrentDictation() {
        let text = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DictationHistorySaveGate.shouldSave(text: text, lastSavedText: lastSavedDictationText,
                                                  enabled: savesDictationHistory) else { return }
        let raw = rawDictationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = DictationHistoryEntry(id: currentDictationHistoryEntryID ?? UUID(),
                                          text: text,
                                          rawText: raw.isEmpty || raw == text ? nil : raw)
        do {
            dictationHistory = try DictationHistoryStore.upsertingAndSaving(
                entry, to: dictationHistoryURL, existing: dictationHistory)
            currentDictationHistoryEntryID = entry.id
            lastSavedDictationText = text
            dictationHistoryMessage = nil
        } catch {
            dictationHistoryMessage = "This transcript could not be saved to history: \(error.localizedDescription)"
        }
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
    }

}
