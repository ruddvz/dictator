import SwiftUI

/// Experimental motion-to-text use screen.
struct UseView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "Step 4 · Experimental",
                    title: "Use your trained words",
                    subtitle: "Capture one word at a time. HushKey shows uncertain matches as rejected instead of guessing.")
                if !model.isMotionInferenceEnabled {
                    eligibilityCard
                }
                controls
                transcriptPanel
                if model.insertion.isEnabled {
                    Label("Accessibility insertion is enabled · \(model.insertion.shortcut.label)", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Advanced diagnostics and comparison") {
                    VStack(alignment: .leading, spacing: 14) {
                        lastPredictionPanel
                        micPanel
                    }
                    .padding(.top, 10)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var eligibilityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Silent use is locked").font(.headline)
                Text(eligibilityMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(nextActionTitle, systemImage: "arrow.right") {
                if model.motion.status != .streaming {
                    model.screen = .setup
                } else if !meetsTemplateProtocol {
                    model.trainingCondition = .silent
                    model.screen = .train
                } else {
                    model.trainingCondition = .silent
                    model.screen = .evaluate
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.25)))
    }

    private var eligibilityMessage: String {
        if model.motion.status != .streaming {
            return "Connect compatible head-tracking headphones and confirm a live motion stream on Setup."
        }
        if model.trainingCondition != .silent {
            return "Evaluation is set to \(model.trainingCondition.rawValue). Silent mouthing needs its own passing evidence."
        }
        if !meetsTemplateProtocol {
            return "Collect 10 examples each for at least 5 words in the Silent condition before evaluation."
        }
        guard let result = model.evaluation else {
            return "Collect the study minimum, then pass the permutation test and separate-session holdout on Evaluate."
        }
        if result.pValue >= 0.05 {
            return "The current silent-motion result does not pass the permutation test. HushKey will not guess."
        }
        if let holdout = result.sessionHoldoutAccuracy, let baseline = result.sessionHoldoutChance, holdout <= baseline {
            return "Held-out sessions do not beat the majority baseline yet. Collect more independent sessions."
        }
        return "The current evidence is incomplete. Check the study size and held-out session result."
    }

    private var meetsTemplateProtocol: Bool {
        model.dataset.vocabulary.count >= 5 &&
        model.dataset.vocabulary.allSatisfy { model.templateCount(for: $0, condition: .silent) >= 10 }
    }

    private var nextActionTitle: String {
        if model.motion.status != .streaming { return "Open Setup" }
        if !meetsTemplateProtocol { return "Continue training" }
        return "Review evidence"
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var model = model
        @Bindable var capture = model.capture
        return GroupBox("Capture") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Capture mode", selection: $model.useCaptureMode) {
                    ForEach(CaptureController.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .disabled(!model.isMotionInferenceEnabled)

                if model.useCaptureMode == .hold {
                    HoldToCaptureButton(
                        title: "Mouth a word",
                        shortcut: model.captureShortcut.label,
                        isCapturing: capture.isCapturing,
                        isEnabled: model.isMotionInferenceEnabled && model.motion.status == .streaming,
                        onBegin: capture.begin,
                        onEnd: capture.end)
                } else {
                    autoControls
                }

                DisclosureGroup("Advanced detection thresholds") {
                    VStack(spacing: 10) {
                        LabeledContent("Maximum distance") {
                            Slider(value: $model.maxDistance, in: 0.2...4).frame(width: 180)
                            Text(String(format: "%.2f", model.maxDistance)).monospacedDigit().frame(width: 36)
                        }
                        LabeledContent("Minimum confidence") {
                            Slider(value: $model.minConfidence, in: 0...0.5).frame(width: 180)
                            Text(String(format: "%.2f", model.minConfidence)).monospacedDigit().frame(width: 36)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption)
            }
            .padding(6)
        }
    }

    private var autoControls: some View {
        @Bindable var capture = model.capture
        let scaleMax = max((capture.threshold ?? 0.05) * 2, 0.02)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(capture.isCalibrating ? "Calibrating… stay still" : "Calibrate noise floor") {
                    capture.calibrate()
                }
                .disabled(capture.isCalibrating || model.motion.status != .streaming)
                if let floor = capture.noiseFloor {
                    Text(String(format: "floor %.4f", floor)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(capture.isCapturing ? Color.red : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
                Text(capture.isCapturing ? "Capturing" : "Listening")
                    .font(.caption)
            }
            LevelMeter(value: capture.energy / scaleMax,
                       marker: capture.threshold.map { $0 / scaleMax },
                       tint: capture.isCapturing ? .red : .blue)
            LabeledContent("Trigger × floor") {
                Slider(value: $capture.triggerRatio, in: 1.5...10).frame(width: 160)
                Text(String(format: "%.1f×", capture.triggerRatio)).monospacedDigit()
            }
            .font(.callout)
            if capture.noiseFloor == nil {
                Text("Calibrate first: keep still for 2 s so the detector learns your resting motion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Transcript

    private var transcriptPanel: some View {
        GroupBox("Transcript") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("Clear", action: model.clearDecoded)
                        .disabled(model.decoded.isEmpty)
                }
                if model.decoded.isEmpty {
                    Text(model.isMotionInferenceEnabled ? "Mouth a trained word…" : "Complete the evidence checks to begin.")
                        .font(.system(size: 28, weight: .regular, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                } else {
                    decodedText
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                }
                Text("Accepted words appear normally. Rejected matches stay faded and will not be inserted.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private var decodedText: Text {
        model.decoded.reduce(Text("")) { text, word in
            let piece = Text(word.text + " ")
            return text + (word.prediction.accepted ? piece : piece.foregroundColor(.secondary.opacity(0.4)))
        }
    }

    // MARK: Diagnostics

    private var lastPredictionPanel: some View {
        GroupBox("Last segment") {
            VStack(alignment: .leading, spacing: 8) {
                if let prediction = model.decoded.last?.prediction {
                    let worst = prediction.ranked.last?.distance ?? 1
                    ForEach(prediction.ranked) { candidate in
                        HStack {
                            Text(candidate.label).frame(width: 70, alignment: .leading)
                            LevelMeter(value: 1 - candidate.distance / max(worst * 1.2, 1e-6),
                                       tint: candidate == prediction.best ? .green : .gray)
                            Text(String(format: "%.2f", candidate.distance))
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    Text(String(format: "Confidence %.2f · %@", prediction.confidence,
                                prediction.accepted ? "accepted" : "rejected"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SignalPlot(title: "Rotation rate", samples: model.lastSegment,
                               channels: SignalPlot.rotation, minScale: 0.05, height: 60)
                } else {
                    Text("DTW distance to each word's closest take appears here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var micPanel: some View {
        GroupBox("Optional on-device speech reference") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button(model.audio.isRunning ? "Stop Mic" : "Start Mic") {
                        Task { await model.toggleMic() }
                    }
                    LevelMeter(value: Double(model.audio.level))
                    Button("Clear", action: model.transcriber.clear)
                }
                Text(model.transcriber.text.isEmpty ? "Speak or whisper to compare against the motion decoder." : model.transcriber.text)
                    .foregroundStyle(model.transcriber.text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                if model.transcriber.isRunning {
                    Text("On-device recognition")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let error = model.audio.error ?? model.transcriber.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}
