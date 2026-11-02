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
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Evaluate",
                           subtitle: "Does the motion really tell your words apart? Tested against chance and held-out sessions.") {
                    MenuPicker(selection: $model.trainingCondition,
                               options: SessionRecorder.Condition.allCases.map { ($0, $0.rawValue) },
                               width: 140)
                }
                LabProgress()

                if let result = model.evaluation {
                    EvaluationResultView(result: result)
                } else {
                    EmptyState(systemImage: "chart.bar.xaxis", title: "No result yet",
                               message: meetsTemplateProtocol ? "Pick the motion features below, then evaluate."
                                   : "Record 10 takes for each of 5 words in this condition first.")
                        .card(padding: 0, style: .outlined)
                }

                evaluationControls
                readinessCard
            }
            .pageLayout()
        }
    }

    private var readinessCard: some View {
        SettingsGroup(title: "Evidence checks",
                      footer: model.trainingCondition == .silent
                          ? "Silent Use unlocks only when every check passes."
                          : "Only silent results can unlock Silent Use.") {
            ReadinessRow(title: "5 or more words",
                         detail: "\(model.dataset.vocabulary.count) in your list",
                         complete: model.dataset.vocabulary.count >= 5)
            ReadinessRow(title: "10 takes per word",
                         detail: "Fewest: \(minimumWordCount)/10",
                         complete: meetsTemplateProtocol)
            ReadinessRow(title: "2 or more sessions",
                         detail: "\(uniqueSessions) recorded",
                         complete: uniqueSessions >= 2)
        }
    }

    private var minimumWordCount: Int {
        model.dataset.vocabulary.map {
            model.templateCount(for: $0, condition: model.trainingCondition)
        }.min() ?? 0
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
                Button(model.isEvaluating ? "Evaluating…" : "Evaluate") { model.evaluate() }
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
            Image(systemName: complete ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 20))
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
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
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
                    Image(systemName: passesAllChecks ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
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
                    Label("Session holdout needs examples from at least two distinct sessions.", systemImage: "info.circle")
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
            Text(value)
                .font(highlight ? .display(28).monospacedDigit() : .display(22, weight: .medium).monospacedDigit())
                .foregroundStyle(highlight ? Theme.ink : Theme.ink2)
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
