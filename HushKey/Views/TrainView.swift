import SwiftUI

struct TrainView: View {
    @Environment(AppModel.self) private var model
    @State private var newWord = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: "Step 2 · Collect examples",
                title: "Train your vocabulary",
                subtitle: "Record one word at a time under voice, whisper, or silent-mouthing conditions. Keep the sessions distinct for a fair holdout test.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 12)

            HSplitView {
                vocabulary
                    .frame(minWidth: 210, idealWidth: 230, maxWidth: 290)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        capturePanel
                        takes
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(20)
                }
                .frame(minWidth: 500)
            }
        }
    }

    private var vocabulary: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack {
                Text("VOCABULARY")
                    .font(.hkCaption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.dataset.vocabulary.count) words")
                    .font(.hkCaption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
            List(selection: $model.selectedWord) {
                ForEach(model.dataset.vocabulary, id: \.self) { word in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(word)
                            Spacer()
                            Text("\(min(model.templateCount(for: word, condition: model.trainingCondition), 10))/10")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(Double(model.templateCount(for: word, condition: model.trainingCondition)), 10), total: 10)
                    }
                    .padding(.vertical, 2)
                    .tag(word)
                    .contextMenu {
                        Button("Delete “\(word)” and its takes", role: .destructive) { model.removeWord(word) }
                    }
                }
            }
            HStack {
                TextField("Add word", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWord)
                Button("Add", systemImage: "plus", action: addWord)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Add word to vocabulary")
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
    }

    private var capturePanel: some View {
        @Bindable var model = model
        let word = model.selectedWord ?? "—"
        return GroupBox("Training setup") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Condition", selection: $model.trainingCondition) {
                    ForEach(SessionRecorder.Condition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Label("Session \(model.experimentSessionID.uuidString.prefix(8))", systemImage: "square.stack.3d.up")
                        .font(.hkCaption.monospaced())
                        .foregroundStyle(.secondary)
                    Button("New session", systemImage: "plus") { model.beginNewExperimentSession() }
                    Spacer()
                }
                Text(conditionGuidance)
                    .foregroundStyle(.secondary)
                HoldToCaptureButton(
                    title: "Capture “\(word)”",
                    shortcut: model.captureShortcut.label,
                    isCapturing: model.capture.isCapturing,
                    isEnabled: model.selectedWord != nil && model.motion.status == .streaming,
                    onBegin: model.capture.begin,
                    onEnd: model.capture.end)
                if model.motion.status != .streaming {
                    Label(model.motion.status.label, systemImage: "headphones")
                        .font(.hkCaption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(6)
        }
    }

    private var conditionGuidance: String {
        switch model.trainingCondition {
        case .normal:
            "Say the selected word at a natural volume while holding capture. Aim for 10 takes across each of at least 5 words."
        case .whisper:
            "Whisper the selected word while holding capture. Keep this condition separate from normal voice and silent mouthing."
        case .silent:
            "Mouth the word without voicing it. Collect 10 takes for each of at least 5 words, across multiple sessions."
        }
    }

    @ViewBuilder
    private var takes: some View {
        if let word = model.selectedWord {
            let takes = model.templates(for: word, condition: model.trainingCondition).reversed()
            GroupBox("\(word) · \(takes.count) \(model.trainingCondition.rawValue.lowercased()) examples") {
                if takes.isEmpty {
                    Text("No takes yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(Array(takes)) { take in
                            TakeTile(template: take, isNew: take.id == model.lastTemplateID) {
                                model.deleteTemplate(take.id)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        } else {
            GroupBox("Start with a word") {
                Label("Add a short word in the vocabulary list, then choose it to capture examples.", systemImage: "plus.circle")
                    .font(.hkCallout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(8)
            }
        }
    }

    private func addWord() {
        model.addWord(newWord)
        newWord = ""
    }
}

private struct TakeTile: View {
    var template: Template
    var isNew: Bool
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SignalPlot(title: "", samples: template.samples, channels: SignalPlot.rotation,
                       minScale: 0.05, height: 44, showsHeader: false)
            HStack {
                Text(String(format: "%.2f s · %d", template.duration, template.samples.count))
                    .font(.hkMeta.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.hkCaption)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(isNew ? Theme.ink : .clear, lineWidth: 1.5))
    }
}
