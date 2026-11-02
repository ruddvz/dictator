import SwiftUI

struct TrainView: View {
    @Environment(AppModel.self) private var model
    @State private var newWord = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Train",
                           subtitle: "Ten takes of each word, five words or more. Keep sessions separate for a fair test.")
                LabProgress()
                HStack(alignment: .top, spacing: Theme.s5) {
                    vocabulary.frame(width: 260)
                    VStack(alignment: .leading, spacing: Theme.s5) {
                        capturePanel
                        takes
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .pageLayout(maxWidth: Theme.homeWidth)
        }
    }

    private var vocabulary: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Words").font(.hkTitle3)
                Spacer()
                Text("\(model.dataset.vocabulary.count)")
                    .font(.hkCallout.monospacedDigit())
                    .foregroundStyle(Theme.ink3)
            }
            HStack(spacing: Theme.s2) {
                TextField("Add a word", text: $newWord)
                    .textFieldStyle(.plain)
                    .font(.hkBody)
                    .onSubmit(addWord)
                Button("Add", systemImage: "plus", action: addWord)
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Add word to vocabulary")
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, Theme.s3)
            .padding(.trailing, 3)
            .frame(height: Theme.controlHeight)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))

            if model.dataset.vocabulary.isEmpty {
                Text("Short, distinct words work best: yes, no, stop, next, send.")
                    .font(.hkCallout)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, Theme.s1)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.dataset.vocabulary, id: \.self) { word in
                        WordRow(word: word,
                                count: model.templateCount(for: word, condition: model.trainingCondition),
                                isSelected: model.selectedWord == word) {
                            model.selectedWord = word
                        }
                        .contextMenu {
                            Button("Delete “\(word)” and its takes", role: .destructive) { model.removeWord(word) }
                        }
                    }
                }
            }
        }
    }

    private var capturePanel: some View {
        @Bindable var model = model
        let word = model.selectedWord ?? "a word"
        return VStack(alignment: .leading, spacing: Theme.s4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("“\(word)”").font(.display(28)).tracking(-0.3)
                    Text(conditionGuidance)
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.s3)
                MenuPicker(selection: $model.trainingCondition,
                           options: SessionRecorder.Condition.allCases.map { ($0, $0.rawValue) },
                           width: 176)
            }
            HoldToCaptureButton(
                title: "Capture “\(word)”",
                shortcut: "Control",
                isCapturing: model.capture.isCapturing,
                isEnabled: model.selectedWord != nil && model.motion.status == .streaming,
                onBegin: model.capture.begin,
                onEnd: model.capture.end)
            if let issue = model.lastTakeIssue {
                Label(issue.message + " It wasn’t saved.", systemImage: "exclamationmark.triangle")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.finishing)
            }
            HStack(spacing: Theme.s2) {
                if model.motion.status != .streaming {
                    Label(model.motion.status.label, systemImage: "headphones")
                        .font(.hkCaption)
                        .foregroundStyle(Theme.finishing)
                } else {
                    Label("Session \(model.experimentSessionID.uuidString.prefix(8))", systemImage: "square.stack.3d.up")
                        .font(.hkCaption.monospaced())
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                Button("New session", systemImage: "plus") { model.beginNewExperimentSession() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.s6 - 4)
        .background(Theme.signalSoft, in: RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
    }

    private var conditionGuidance: String {
        switch model.trainingCondition {
        case .normal:
            "Say it out loud while you hold capture."
        case .whisper:
            "Whisper it while you hold capture."
        case .silent where model.selectedWord == TemplateClassifier.restLabel:
            "Hold capture with your mouth closed and still. HushKey learns to ignore this, never types it."
        case .silent:
            "Mouth it without a sound while you hold capture, or hold Control. Add a word “\(TemplateClassifier.restLabel)” so stray movement is ignored."
        }
    }

    @ViewBuilder
    private var takes: some View {
        if let word = model.selectedWord {
            let takes = model.templates(for: word, condition: model.trainingCondition).reversed()
            VStack(alignment: .leading, spacing: Theme.s3) {
                HStack {
                    Text("Takes").font(.hkTitle3)
                    Spacer()
                    Text("\(takes.count) \(model.trainingCondition.rawValue.lowercased())")
                        .font(.hkCallout.monospacedDigit())
                        .foregroundStyle(Theme.ink3)
                }
                if takes.isEmpty {
                    EmptyState(systemImage: "waveform.path", title: "No takes yet",
                               message: "Hold capture and mouth “\(word)”. Each take appears here.")
                        .card(padding: 0, style: .outlined)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.s3)], spacing: Theme.s3) {
                        ForEach(Array(takes)) { take in
                            TakeTile(template: take, isNew: take.id == model.lastTemplateID) {
                                model.deleteTemplate(take.id)
                            }
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .animation(Theme.gentle, value: takes.count)
                }
            }
        } else {
            EmptyState(systemImage: "plus.circle", title: "Start with a word",
                       message: "Add a short word on the left, then pick it to record takes.")
                .card(padding: 0, style: .outlined)
        }
    }

    private func addWord() {
        model.addWord(newWord)
        newWord = ""
    }
}

private struct WordRow: View {
    var word: String
    var count: Int
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(word).font(.hkBody.weight(isSelected ? .semibold : .regular))
                    Spacer()
                    if count >= 10 {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.signal)
                    } else {
                        Text("\(count)/10")
                            .font(.hkCaption.monospacedDigit())
                            .foregroundStyle(Theme.ink2)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline)
                        Capsule().fill(Theme.signal)
                            .frame(width: geo.size.width * min(CGFloat(count), 10) / 10)
                    }
                }
                .frame(height: 3)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2 + 2)
            .background(isSelected ? Theme.selection : hovering ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.gentle, value: count)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct TakeTile: View {
    var template: Template
    var isNew: Bool
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SignalPlot(title: "", samples: template.samples, channels: SignalPlot.rotation,
                       minScale: 0.05, height: 44, showsHeader: false)
            HStack {
                Text(String(format: "%.2f s · %d", template.duration, template.samples.count))
                    .font(.hkMeta.monospacedDigit())
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Button("Delete", systemImage: "trash", action: onDelete)
                    .buttonStyle(IconButtonStyle())
                    .opacity(hovering ? 1 : 0)
            }
        }
        .padding(Theme.s2 + 2)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(isNew ? Theme.signal : Theme.hairline, lineWidth: isNew ? 1.5 : 1))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
