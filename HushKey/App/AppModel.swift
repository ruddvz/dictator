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
        case setup = "Setup"
        case train = "Train"
        case evaluate = "Evaluate"
        case use = "Use"
        case settings = "Settings & Data"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .setup: "headphones"
            case .train: "square.stack.3d.up"
            case .evaluate: "chart.bar.xaxis"
            case .use: "text.bubble"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    let motion = HeadphoneMotionService()
    let audio = AudioService()
    let transcriber = MicTranscriber()
    let insertion = TextInsertionService()
    let capture = CaptureController()
    let recorder = SessionRecorder()

    var screen: Screen = .setup {
        didSet { syncCaptureMode() }
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
    @ObservationIgnored private var started = false

    init() {
        selectedWord = dataset.vocabulary.first
        insertion.onInsertShortcut = { [weak self] in self?.insertLatestPrediction() }
        rebuildClassifier()
    }

    func start() {
        guard !started else { return }
        started = true
        motion.onSample = { [weak self] sample in self?.ingest(sample) }
        capture.onSegment = { [weak self] segment in self?.handleSegment(segment) }
        motion.start()
        audio.refreshDevices()
        installKeyMonitor()
    }

    private func ingest(_ sample: MotionSample) {
        capture.ingest(sample)
        recorder.record(sample)
    }

    private func syncCaptureMode() {
        capture.autoEnabled = isMotionInferenceEnabled && screen == .use && useCaptureMode == .auto
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
        case .setup, .evaluate:
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

    // MARK: Mic

    func toggleMic() async {
        if audio.isRunning {
            transcriber.stop()
            audio.stop()
        } else {
            await audio.start()
            if audio.isRunning { await transcriber.start(sink: audio.sink) }
        }
    }
}
