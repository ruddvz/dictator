import SwiftUI

struct EvaluateView: View {
    @Environment(AppModel.self) private var model

    private var meetsTemplateProtocol: Bool { model.meetsTemplateProtocol(condition: model.trainingCondition) }

    private var completeSessions: Int { model.completeSessionCount(condition: model.trainingCondition) }

    /// This run's result, or for silent takes the background check that also unlocks Silent Use,
    /// so a result is on screen after a relaunch without running Evaluate again.
    private var result: Evaluation? {
        model.evaluation ?? (model.trainingCondition == .silent ? model.silentEvidence : nil)
    }

    private var isChecking: Bool {
        model.isEvaluating || (model.trainingCondition == .silent && model.evaluation == nil && model.isCheckingSilentEvidence)
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Evaluate",
                           subtitle: "Does the motion really tell your words apart? Tested against chance and held-out sessions.") {
                    MenuPicker(selection: $model.trainingCondition,
                               options: SessionRecorder.Condition.allCases.map { ($0, $0.rawValue) },
                               width: 176)
                }
                LabProgress()

                if let result {
                    EvaluationResultView(result: result)
                } else if isChecking {
                    EmptyState(icon: .clock, title: "Checking your takes…",
                               message: "Comparing every take with every other, and against chance.")
                        .card(padding: 0, style: .outlined)
                } else {
                    EmptyState(icon: .evaluate, title: "No result yet",
                               message: meetsTemplateProtocol ? "Pick the motion features below, then evaluate."
                                   : "Record \(AppModel.takesPerWord) takes of each of \(AppModel.minimumWords) words in this condition first.")
                        .card(padding: 0, style: .outlined)
                }

                evaluationControls
                readinessCard
            }
            .pageLayout()
        }
    }

    private var readinessCard: some View {
        SettingsGroup(title: "Before you evaluate",
                      footer: model.trainingCondition == .silent
                          ? "Silent Use unlocks when the result beats chance, including on a session it never trained on."
                          : "Only silent results can unlock Silent Use.") {
            ReadinessRow(title: "\(AppModel.minimumWords) or more words",
                         detail: "\(model.dataset.vocabulary.count) in your list",
                         complete: model.dataset.vocabulary.count >= AppModel.minimumWords)
            ReadinessRow(title: "\(AppModel.takesPerWord) takes per word",
                         detail: takesDetail,
                         complete: meetsTemplateProtocol)
            ReadinessRow(title: "2 sessions with every word",
                         detail: "\(completeSessions) of 2 · each needs \(AppModel.sessionTakesPerWord)+ takes of every word",
                         complete: completeSessions >= 2)
        }
    }

    private var takesDetail: String {
        let needed = model.takesStillNeeded(condition: model.trainingCondition)
        guard !needed.isEmpty else { return "Every word is done" }
        return "Still to record: " + needed.prefix(4).map { "\($0.word) \($0.needed)" }.joined(separator: ", ")
            + (needed.count > 4 ? "…" : "")
    }

    private var evaluationControls: some View {
        @Bindable var model = model
        return SettingsGroup(title: "Analysis") {
            SettingsRow(title: "Motion features", detail: "Which signals the classifier may use.") {
                HStack(spacing: Theme.s2) {
                    FeatureToggle(title: "Acceleration", option: .acceleration)
                    FeatureToggle(title: "Rotation", option: .rotation)
                    FeatureToggle(title: "Attitude", option: .attitude)
                }
            }
            SettingsRow(title: model.isEvaluating ? "Evaluating…" : "Run the evaluation",
                        detail: model.trainingCondition == .silent
                            ? (model.isMotionInferenceEnabled ? "Silent Use is unlocked." : "Silent Use is locked until every check passes.")
                            : "Compares this condition only.",
                        detailTint: model.isMotionInferenceEnabled && model.trainingCondition == .silent ? Theme.success : Theme.ink2) {
                Button(model.isEvaluating ? "Evaluating…" : result == nil ? "Evaluate" : "Evaluate again") { model.evaluate() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isEvaluating || model.featureSet.isEmpty || !meetsTemplateProtocol)
            }
        }
    }
}

private struct ReadinessRow: View {
    var title: String
    var detail: String
    var complete: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Glyph(complete ? .checkCircle : .record)
                .hushIconSize(25)
                .foregroundStyle(complete ? Theme.signal : Theme.ink3)
                .accessibilityLabel(complete ? "Done" : "Not yet")
        }
        .accessibilityElement(children: .combine)
    }
}

/// Selectable chip; reads better than three checkboxes in a row.
private struct FeatureToggle: View {
    @Environment(AppModel.self) private var model
    var title: String
    var option: FeatureSet

    var body: some View {
        let on = model.featureSet.contains(option)
        Button {
            if on { model.featureSet.remove(option) } else { model.featureSet.insert(option) }
        } label: {
            HStack(spacing: 5) {
                if on { Glyph(.check).hushIconSize(12) }
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(on ? Theme.signal : Theme.ink2)
            .padding(.horizontal, Theme.s3 - 2)
            .frame(height: 30)
            .background(on ? Theme.signalSoft : Theme.sheet, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Theme.signal.opacity(0.5) : Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Theme.snappy, value: on)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

private struct EvaluationResultView: View {
    var result: Evaluation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
                HStack(spacing: Theme.s3) {
                    Glyph(passesAllChecks ? .checkCircle : .warning)
                        .hushIconSize(28)
                        .foregroundStyle(passesAllChecks ? Theme.signal : Theme.finishing)
                    Text(verdict)
                        .font(.hkRowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RowDivider()
                HStack(spacing: Theme.s6) {
                    metric("Leave-one-out", percent(result.accuracy), highlight: true)
                    metric("Majority baseline", percent(result.chance))
                    metric("Permutation p", result.pValue < 0.001 ? "< 0.001" : String(format: "%.3f", result.pValue))
                }
                if let holdout = result.sessionHoldoutAccuracy, let baseline = result.sessionHoldoutChance {
                    HStack(spacing: Theme.s6) {
                        metric("Held-out sessions", percent(holdout), highlight: true)
                        metric("Holdout baseline", percent(baseline))
                        Text("\(result.sessionHoldoutSessions) folds")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }
                } else {
                    Label("Session holdout needs examples from at least two distinct sessions.", icon: .info)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                }
                DisclosureGroup("Confusion matrix · \(result.templateCount) examples") {
                    confusionMatrix
                        .padding(.top, 10)
                }
                .font(.hkCallout.weight(.medium))
                .tint(Theme.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.s6 - 4)
            .background(passesAllChecks ? Theme.signalSoft : Theme.well,
                        in: RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
    }

    private var confusionMatrix: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                Text("actual ↓ / predicted →").font(.hkMeta).foregroundStyle(Theme.ink2)
                ForEach(result.labels, id: \.self) { Text($0).font(.hkMeta).lineLimit(1) }
            }
            ForEach(result.labels.indices, id: \.self) { row in
                let total = max(result.confusion[row].reduce(0, +), 1)
                GridRow {
                    Text(result.labels[row]).font(.hkMeta).gridColumnAlignment(.trailing)
                    ForEach(result.labels.indices, id: \.self) { col in
                        let count = result.confusion[row][col]
                        Text("\(count)")
                            .font(.hkCaption.monospacedDigit())
                            .frame(minWidth: 36, minHeight: 24)
                            .background((row == col ? Theme.success : Theme.danger)
                                .opacity(Double(count) / Double(total) * 0.7))
                    }
                }
            }
        }
        .accessibilityLabel("Confusion matrix. Rows are actual words and columns are predicted words.")
    }

    private var passesPermutation: Bool { result.pValue < 0.05 }

    private var passesAllChecks: Bool { AppModel.evidenceUnlocksSilentUse(result) }

    private var verdict: String {
        guard result.accuracy > result.chance else {
            return "Leave-one-out accuracy did not beat the majority baseline. Collect more examples or compare another feature set."
        }
        guard passesPermutation else {
            return "Not distinguishable from chance yet. Collect more examples or compare another feature set."
        }
        guard let holdout = result.sessionHoldoutAccuracy,
              let baseline = result.sessionHoldoutChance else {
            return "The permutation check passed. Record every word in a second session so one can be held out."
        }
        guard holdout > baseline else {
            return "The permutation check passed, but held-out sessions did not beat their majority baseline."
        }
        guard result.templateCount >= AppModel.minimumEvidenceTemplates else {
            return "Promising, but \(AppModel.minimumEvidenceTemplates) or more takes are needed to trust it."
        }
        return "Your words are distinguishable, including on sessions held out from training."
    }

    private func metric(_ title: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.hkCaption).foregroundStyle(Theme.ink2)
            Text(value)
                .font(highlight ? .display(28).monospacedDigit() : .display(22, weight: .medium).monospacedDigit())
                .foregroundStyle(highlight ? Theme.ink : Theme.ink2)
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
