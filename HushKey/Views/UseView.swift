import SwiftUI

/// Experimental motion-to-text use screen.
struct UseView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Silent Use",
                           subtitle: "Hold Control in any app and mouth a trained word. Unsure matches are shown faded, never typed.") {
                    if model.insertion.isEnabled {
                        StatusChip(title: "Types with \(model.insertion.shortcut.label)", systemImage: "checkmark.shield",
                                   tint: Theme.signal)
                    }
                }
                LabProgress()
                if !model.isMotionInferenceEnabled {
                    LabHero(symbol: "lock.shield", tint: Theme.finishing, title: "Silent Use is locked",
                            message: eligibilityMessage) {
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
                        .buttonStyle(PrimaryButtonStyle())
                    } metrics: {
                        EmptyView()
                    }
                }
                transcriptPanel
                controls
                SettingsGroup(title: "Diagnostics") {
                    lastPredictionPanel
                }
            }
            .pageLayout()
        }
    }

    private var eligibilityMessage: String {
        let needed = model.takesStillNeeded(condition: .silent)
        let words = model.dataset.vocabulary.count
        var training: String?
        if words < AppModel.minimumWords {
            let missing = AppModel.minimumWords - words
            training = "add \(missing) more \(missing == 1 ? "word" : "words") on Train"
        } else if !needed.isEmpty {
            let total = needed.reduce(0) { $0 + $1.needed }
            training = "record \(total) more silent \(total == 1 ? "take" : "takes") ("
                + needed.prefix(3).map { "\($0.word) \($0.needed)" }.joined(separator: ", ")
                + (needed.count > 3 ? "…" : "") + ")"
        }
        if model.motion.status != .streaming {
            return "Connect your AirPods" + (training.map { ", then \($0)." } ?? ".")
        }
        if let training {
            return training.prefix(1).uppercased() + training.dropFirst() + "."
        }
        if model.completeSessionCount(condition: .silent) < 2 {
            return "Record every word \(AppModel.sessionTakesPerWord)+ times in a second session (Train → New session), so one can be held out."
        }
        guard let result = model.silentEvidence else {
            return model.isCheckingSilentEvidence
                ? "Checking your silent takes…"
                : "Run Evaluate. It must beat chance and held-out sessions."
        }
        if result.sessionHoldoutAccuracy == nil {
            return "Record every word in a second session (Train → New session) so one can be held out."
        }
        if result.pValue >= 0.05 {
            return "The result isn’t clear of chance yet. HushKey won’t guess."
        }
        if let holdout = result.sessionHoldoutAccuracy, let baseline = result.sessionHoldoutChance, holdout <= baseline {
            return "Held-out sessions don’t beat the baseline yet. Record another session."
        }
        return "The evidence is incomplete. Check Evaluate."
    }

    private var meetsTemplateProtocol: Bool { model.meetsTemplateProtocol(condition: .silent) }

    private var nextActionTitle: String {
        if model.motion.status != .streaming { return "Connect AirPods" }
        if !meetsTemplateProtocol { return "Continue training" }
        return "Review evidence"
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var model = model
        @Bindable var capture = model.capture
        return SettingsGroup(title: "Capture") {
            SettingsRow(title: "Capture mode",
                        detail: model.useCaptureMode == .hold ? "Hold Control, or \(model.captureShortcut.label) here, while you mouth a word."
                            : "Starts on its own when you move.") {
                MenuPicker(selection: $model.useCaptureMode,
                           options: CaptureController.Mode.allCases.map { ($0, $0.rawValue) })
                    .disabled(!model.isMotionInferenceEnabled)
            }
            GroupRow {
                if model.useCaptureMode == .hold {
                    HoldToCaptureButton(
                        title: "Mouth a word",
                        shortcut: "Control",
                        isCapturing: capture.isCapturing,
                        isEnabled: model.isMotionInferenceEnabled && model.motion.status == .streaming,
                        onBegin: capture.begin,
                        onEnd: capture.end)
                    if model.isMotionInferenceEnabled && model.motion.status == .streaming {
                        HeadStillnessIndicator(isMoving: capture.headIsMoving)
                    }
                } else if model.isMotionInferenceEnabled && model.motion.status == .streaming {
                    autoControls
                } else {
                    Label("Auto capture unlocks with the evidence and a live motion stream.", systemImage: "lock.shield")
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                }
            }
            SettingsRow(title: "Type into the front app",
                        detail: model.insertion.isEnabled
                            ? "Accepted words go straight into the field you’re in. Rejected ones never do."
                            : "Turn on text insertion in Settings first. Until then words stay here.",
                        detailTint: model.insertion.isEnabled ? Theme.ink2 : Theme.finishing) {
                Toggle("", isOn: $model.silentTypesIntoFrontApp)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.signal)
            }
            SettingsRow(title: "Maximum distance", detail: "Lower is stricter.") {
                HStack(spacing: Theme.s2) {
                    Slider(value: $model.maxDistance, in: 0.2...4).frame(width: 150).tint(Theme.signal)
                    Text(String(format: "%.2f", model.maxDistance)).font(.hkCallout.monospacedDigit()).frame(width: 40)
                }
            }
            SettingsRow(title: "Minimum confidence", detail: "Higher rejects more.") {
                HStack(spacing: Theme.s2) {
                    Slider(value: $model.minConfidence, in: 0...0.5).frame(width: 150).tint(Theme.signal)
                    Text(String(format: "%.2f", model.minConfidence)).font(.hkCallout.monospacedDigit()).frame(width: 40)
                }
            }
        }
    }

    private var autoControls: some View {
        @Bindable var capture = model.capture
        let scaleMax = max((capture.threshold ?? 0.05) * 2, 0.02)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(capture.isCalibrating ? "Calibrating… stay still" : "Calibrate") {
                    capture.calibrate()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(capture.isCalibrating || model.motion.status != .streaming)
                if let floor = capture.noiseFloor {
                    Text(String(format: "floor %.4f", floor)).font(.hkCaption.monospacedDigit()).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Circle()
                    .fill(capture.isCapturing ? Theme.signal : Theme.ink2.opacity(0.3))
                    .frame(width: 10, height: 10)
                Text(capture.isCapturing ? "Capturing" : "Listening")
                    .font(.hkCaption)
            }
            LevelMeter(value: capture.energy / scaleMax,
                       marker: capture.threshold.map { $0 / scaleMax },
                       tint: capture.isCapturing ? Theme.listening : Theme.finishing)
            LabeledContent("Trigger × floor") {
                Slider(value: $capture.triggerRatio, in: 1.5...10).frame(width: 160).tint(Theme.signal)
                Text(String(format: "%.1f×", capture.triggerRatio)).monospacedDigit()
            }
            .font(.hkCallout)
            if capture.noiseFloor == nil {
                Text("Calibrate first: keep still for 2 s so the detector learns your resting motion.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    // MARK: Transcript

    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Transcript").font(.hkTitle3)
                Spacer()
                Button("Clear", action: model.clearDecoded)
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.decoded.isEmpty)
            }
            Group {
                if !model.decoded.contains(where: { !isRest($0) }) {
                    Text(model.isMotionInferenceEnabled ? "Mouth a trained word…" : "Pass the evidence checks to begin.")
                        .foregroundStyle(Theme.ink3)
                } else {
                    decodedText.textSelection(.enabled)
                }
            }
            .font(.display(24, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(Theme.s5 - 4)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    /// The "nothing" class is how stray movement is ignored; it never belongs in the transcript.
    private func isRest(_ word: DecodedWord) -> Bool {
        word.prediction.best?.label == TemplateClassifier.restLabel
    }

    private var decodedText: Text {
        model.decoded.filter { !isRest($0) }.reduce(Text("")) { text, word in
            let piece = Text(word.text + " ")
            return text + (word.prediction.accepted ? piece : piece.foregroundColor(Theme.ink3.opacity(0.6)))
        }
    }

    // MARK: Diagnostics

    private var lastPredictionPanel: some View {
        GroupRow {
            VStack(alignment: .leading, spacing: 8) {
                if let prediction = model.decoded.last?.prediction {
                    let worst = prediction.ranked.last?.distance ?? 1
                    ForEach(prediction.ranked) { candidate in
                        HStack {
                            Text(candidate.label).frame(width: 70, alignment: .leading)
                            LevelMeter(value: 1 - candidate.distance / max(worst * 1.2, 1e-6),
                                       tint: candidate == prediction.best ? Theme.signal : Theme.ink3)
                            Text(String(format: "%.2f", candidate.distance))
                                .font(.hkCaption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    Text(String(format: "Confidence %.2f · %@", prediction.confidence,
                                prediction.accepted ? "accepted" : "rejected"))
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                    if let issue = model.lastTakeIssue {
                        Label(issue.message, systemImage: "exclamationmark.triangle")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.finishing)
                    }
                    SignalPlot(title: "Rotation rate", samples: model.lastSegment,
                               channels: SignalPlot.rotation, minScale: 0.05, height: 60)
                } else {
                    Text("After a capture, each word’s match distance shows here.")
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}
