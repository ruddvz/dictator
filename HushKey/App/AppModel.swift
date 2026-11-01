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
            case .setup: "headphones"
            case .train: "square.stack.3d.up"
            case .evaluate: "chart.bar.xaxis"
            case .use: "text.bubble"
            case .personalization: "text.badge.plus"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    let motion = HeadphoneMotionService()
    let audio = AudioService()
    let transcriber = MicTranscriber()
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
    var dictationCaptureBehavior: DictationCaptureBehavior = DictationCaptureBehavior(
        rawValue: UserDefaults.standard.string(forKey: DictationCaptureBehavior.preferenceKey) ?? "") ?? .hold {
        didSet {
            UserDefaults.standard.set(dictationCaptureBehavior.rawValue, forKey: DictationCaptureBehavior.preferenceKey)
            if started { installDictationShortcut() }
        }
    }
    private(set) var dictationShortcutStatus = "Shortcut is not registered yet."
    var dictationTerms = UserDefaults.standard.string(forKey: "dictationTerms") ?? "" {
        didSet { UserDefaults.standard.set(dictationTerms, forKey: "dictationTerms") }
    }
    var dictationSnippets = UserDefaults.standard.string(forKey: "dictationSnippets") ?? "" {
        didSet { UserDefaults.standard.set(dictationSnippets, forKey: "dictationSnippets") }
    }
    var dictationLanguage = UserDefaults.standard.string(forKey: "dictationLanguage") ?? "en-US" {
        didSet { UserDefaults.standard.set(dictationLanguage, forKey: "dictationLanguage") }
    }
    var dictationMode = DictationMode(rawValue: UserDefaults.standard.string(forKey: "dictationMode") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(dictationMode.rawValue, forKey: "dictationMode") }
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
    private(set) var dictationHistory: [DictationHistoryEntry] = DictationHistoryStore.load()
    private(set) var didInsertCurrentDictation = false
    private(set) var rawDictationText = ""
    private(set) var transformUndoOriginalText: String?
    private(set) var transformUndoOutputText: String?
    var canUndoLocalTransform: Bool {
        guard let output = transformUndoOutputText else { return false }
        return !didInsertCurrentDictation && !audio.isRunning && !isFinalizingDictation && transcriber.text == output
    }
    private(set) var activeDictationMode: DictationMode = .natural
    private(set) var activeDictationTarget: String?
    private(set) var usedNearbyTextHints = false
    private(set) var isFinalizingDictation = false
    @ObservationIgnored private var lastSavedDictationText: String?

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
    @ObservationIgnored private var started = false
    @ObservationIgnored private var motionStarted = false
    @ObservationIgnored private var dictationShortcutHeld = false
    @ObservationIgnored private var dictationStartGeneration = 0

    init() {
        selectedWord = dataset.vocabulary.first
        insertion.onInsertShortcut = { [weak self] in self?.insertLatestOutput() }
        insertion.onUndoShortcut = { [weak self] in self?.undoLastInsertion() }
        rebuildClassifier()
    }

    func start() {
        guard !started else { return }
        started = true
        motion.onSample = { [weak self] sample in self?.ingest(sample) }
        capture.onSegment = { [weak self] segment in self?.handleSegment(segment) }
        audio.refreshDevices()
        installKeyMonitor()
        installDictationShortcut()
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
        case .dictation, .transforms, .files, .setup, .evaluate, .personalization:
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
        if screen == .dictation || screen == .transforms {
            insertDictationText()
        } else {
            insertLatestPrediction()
        }
    }

    func insertDictationText() {
        guard !isFinalizingDictation, !transcriber.isFinalizing else {
            insertion.report("Wait for the local transcript to finish before inserting it.")
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
        if audio.isRunning {
            stopDictation()
        }
        saveCurrentDictation()
        screen = .dictation
        transcriber.clear()
        rawDictationText = ""
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        lastSavedDictationText = nil
        await startDictation()
    }

    func toggleDictation() async {
        if audio.isRunning {
            stopDictation()
        } else {
            await startNewDictation()
        }
    }

    func clearDictationHistory() {
        dictationHistory.removeAll()
        DictationHistoryStore.save(dictationHistory)
        if !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing {
            transcriber.clear()
            lastSavedDictationText = nil
            didInsertCurrentDictation = false
        }
    }

    func restoreDictation(_ entry: DictationHistoryEntry, useRawText: Bool = false) {
        guard !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing else { return }
        transcriber.replaceText(useRawText ? (entry.rawText ?? entry.text) : entry.text)
        rawDictationText = entry.rawText ?? entry.text
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        lastSavedDictationText = entry.text
        screen = .dictation
    }

    func restoreRawTranscript() {
        guard !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing,
              !rawDictationText.isEmpty else { return }
        transcriber.replaceText(rawDictationText)
        clearLocalTransformUndo()
    }

    func clearCurrentDictation() {
        guard !audio.isRunning, !isFinalizingDictation, !transcriber.isFinalizing else { return }
        transcriber.clear()
        rawDictationText = ""
        clearLocalTransformUndo()
        didInsertCurrentDictation = false
        insertion.clearUndoRecord()
        lastSavedDictationText = nil
    }

    func requestNearbyTextAccess() {
        _ = insertion.requestAccessibilityAccessForContext()
    }

    private func startDictation() async {
        guard !isFinalizingDictation, !transcriber.isFinalizing else { return }
        dictationStartGeneration += 1
        let generation = dictationStartGeneration
        let target = NSWorkspace.shared.frontmostApplication
        let isHushKey = target?.bundleIdentifier == "com.ruddvz.hushkey"
        activeDictationTarget = isHushKey ? nil : target?.localizedName
        activeDictationMode = DictationMode.resolved(dictationMode,
                                                      bundleIdentifier: isHushKey ? nil : target?.bundleIdentifier)
        let nearbyHints = usesNearbyTextHints ? insertion.nearbyContextHints() : []
        usedNearbyTextHints = !nearbyHints.isEmpty

        await audio.start()
        guard generation == dictationStartGeneration, audio.isRunning else { return }
        let customWords = DictationVocabulary.terms(from: dictationTerms)
        let modeHints: [String]
        switch activeDictationMode {
        case .message: modeHints = ["DM", "FYI", "ASAP", "RSVP", "TL;DR"]
        case .email: modeHints = ["subject", "greeting", "regards", "sincerely", "attachment", "forward"]
        case .code: modeHints = ["underscore", "camelCase", "snake_case", "open parenthesis", "close parenthesis", "semicolon", "arrow"]
        case .automatic, .natural: modeHints = []
        }
        let started = await transcriber.start(sink: audio.sink, localeIdentifier: dictationLanguage,
                                              contextualStrings: Array(Set(dataset.vocabulary + customWords + modeHints + nearbyHints)).prefix(100).map { $0 })
        guard generation == dictationStartGeneration, audio.isRunning else {
            transcriber.stop()
            audio.stop()
            return
        }
        if !started { audio.stop() }
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
                                                                  cleanupFillers: cleansDictationFillers)
            transcriber.replaceText(processed)
            saveCurrentDictation()
            isFinalizingDictation = false
        }
    }

    private func saveCurrentDictation() {
        let text = transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard savesDictationHistory, !text.isEmpty, text != lastSavedDictationText else { return }
        let raw = rawDictationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = DictationHistoryEntry(text: text, rawText: raw.isEmpty || raw == text ? nil : raw)
        dictationHistory.insert(entry, at: 0)
        dictationHistory = Array(dictationHistory.prefix(50))
        lastSavedDictationText = text
        DictationHistoryStore.save(dictationHistory)
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
