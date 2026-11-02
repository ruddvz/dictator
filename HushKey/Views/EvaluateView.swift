import SwiftUI

struct EvaluateView: View {
    @Environment(AppModel.self) private var model

    private var meetsTemplateProtocol: Bool {
        model.dataset.vocabulary.count >= 5 &&
        model.dataset.vocabulary.allSatisfy { model.templateCount(for: $0, condition: model.trainingCondition) >= 10 }
    }

    private var uniqueSessions: Int {
        Set(model.templatesForSelectedCondition.map(\.sessionID)).count
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "Step 3 · Check evidence",
                    title: "Evaluate the signal",
                    subtitle: "Compare recognition with a majority baseline and test on sessions that were held out during training.")

                GroupBox("Study condition") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Evaluate", selection: $model.trainingCondition) {
                            ForEach(SessionRecorder.Condition.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(conditionNote)
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(8)
                }

                readinessCard
                evaluationControls

                if let result = model.evaluation {
                    EvaluationResultView(result: result)
                } else {
                    ContentUnavailableView(
                        "No evaluation yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text(meetsTemplateProtocol
                                          ? "Choose features and run Evaluate to see the results."
                                          : "Collect at least 10 examples for each of 5 words in this condition."))
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .pageLayout()
        }
    }

    private var readinessCard: some View {
        GroupBox("Before a result can unlock silent use") {
            VStack(alignment: .leading, spacing: 10) {
                ReadinessRow(
                    title: "5 or more words",
                    detail: "\(model.dataset.vocabulary.count) words in the vocabulary",
                    complete: model.dataset.vocabulary.count >= 5)
                ReadinessRow(
                    title: "10 examples per word",
                    detail: "Fewest for any word: \(minimumWordCount)/10",
                    complete: meetsTemplateProtocol)
                ReadinessRow(
                    title: "At least 2 sessions",
                    detail: "\(uniqueSessions) distinct sessions in this condition",
                    complete: uniqueSessions >= 2)
                Text("Evaluation can run once the first two study-size checks pass. Silent use also requires significant permutation results and held-out session accuracy above baseline.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 2)
            }
            .padding(8)
        }
    }

    private var minimumWordCount: Int {
        model.dataset.vocabulary.map {
            model.templateCount(for: $0, condition: model.trainingCondition)
        }.min() ?? 0
    }

    private var evaluationControls: some View {
        @Bindable var model = model
        return GroupBox("Analysis") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Features")
                        .font(.hkCallout.weight(.medium))
                    FeatureToggle(title: "Acceleration", option: .acceleration)
                    FeatureToggle(title: "Rotation", option: .rotation)
                    FeatureToggle(title: "Attitude", option: .attitude)
                    Spacer(minLength: 8)
                    Button(model.isEvaluating ? "Evaluating…" : "Evaluate") {
                        model.evaluate()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isEvaluating || model.featureSet.isEmpty || !meetsTemplateProtocol)
                }
                if model.trainingCondition == .silent {
                    Label(model.isMotionInferenceEnabled
                          ? "Silent use is enabled by the current evidence."
                          : "Silent use remains locked until every evidence check passes.",
                          systemImage: model.isMotionInferenceEnabled ? "checkmark.shield" : "lock.shield")
                        .font(.hkCaption)
                        .foregroundStyle(model.isMotionInferenceEnabled ? .green : .secondary)
                }
            }
            .padding(8)
        }
    }

    private var conditionNote: String {
        if model.trainingCondition == .silent {
            return "Only silent-mouthing results can enable the experimental Use screen. Voice and whisper results remain separate comparisons."
        }
        return "This result compares the selected condition only. It does not enable silent-mouthing inference."
    }
}

private struct ReadinessRow: View {
    var title: String
    var detail: String
    var complete: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(complete ? Color.green : Theme.ink2)
                .accessibilityHidden(true)
            Text(title).font(.hkCallout.weight(.medium))
            Spacer()
            Text(detail).font(.hkCaption).foregroundStyle(Theme.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FeatureToggle: View {
    @Environment(AppModel.self) private var model
    var title: String
    var option: FeatureSet

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { model.featureSet.contains(option) },
            set: { on in
                if on { model.featureSet.insert(option) } else { model.featureSet.remove(option) }
            }))
        .toggleStyle(.checkbox)
    }
}

private struct EvaluationResultView: View {
    var result: Evaluation

    var body: some View {
        GroupBox("Results") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 26) {
                    metric("Leave-one-out", percent(result.accuracy), highlight: true)
                    metric("Majority baseline", percent(result.chance))
                    metric("Permutation p", result.pValue < 0.001 ? "< 0.001" : String(format: "%.3f", result.pValue))
                }
                if let holdout = result.sessionHoldoutAccuracy, let baseline = result.sessionHoldoutChance {
                    Divider()
                    HStack(spacing: 26) {
                        metric("Held-out sessions", percent(holdout), highlight: true)
                        metric("Holdout baseline", percent(baseline))
                        Text("\(result.sessionHoldoutSessions) folds")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }
                } else {
                    Label("Session holdout needs examples from at least two distinct sessions.", systemImage: "info.circle")
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                }
                Text(verdict)
                    .font(.hkCallout.weight(.medium))
                    .foregroundStyle(passesAllChecks ? .green : .orange)
                DisclosureGroup("Confusion matrix · \(result.templateCount) examples") {
                    confusionMatrix
                        .padding(.top, 10)
                }
                .font(.hkCallout.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
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

    private var passesAllChecks: Bool {
        guard result.templateCount >= 50,
              result.accuracy > result.chance,
              passesPermutation,
              let holdout = result.sessionHoldoutAccuracy,
              let baseline = result.sessionHoldoutChance else { return false }
        return holdout > baseline
    }

    private var verdict: String {
        guard result.accuracy > result.chance else {
            return "Leave-one-out accuracy did not beat the majority baseline. Collect more examples or compare another feature set."
        }
        guard passesPermutation else {
            return "Not distinguishable from chance yet. Collect more examples or compare another feature set."
        }
        guard let holdout = result.sessionHoldoutAccuracy,
              let baseline = result.sessionHoldoutChance else {
            return "The permutation check passed, but examples from at least two sessions are needed for a holdout result."
        }
        guard holdout > baseline else {
            return "The permutation check passed, but held-out sessions did not beat their majority baseline."
        }
        return "This study beat the majority baseline in cross-validation and held-out sessions."
    }

    private func metric(_ title: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.hkCaption).foregroundStyle(Theme.ink2)
            Text(value).font(highlight ? .title2.bold().monospacedDigit() : .title3.monospacedDigit())
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
