import SwiftUI

struct TrainView: View {
    @Environment(AppModel.self) private var model
    @State private var newWord = ""
    @State private var wordToDelete: String?

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
        .confirmationDialog("Delete “\(wordToDelete ?? "")” and its takes?",
                            isPresented: Binding(get: { wordToDelete != nil }, set: { if !$0 { wordToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let word = wordToDelete { model.removeWord(word) }
                wordToDelete = nil
            }
        } message: {
            Text("Every take of this word, in every condition, is removed from this Mac.")
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
                Button("Add", icon: .plus, action: addWord)
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
                                isSelected: model.selectedWord == word,
                                action: { model.selectedWord = word },
                                onDelete: { wordToDelete = word })
                        .contextMenu {
                            Button("Delete “\(word)” and its takes…", role: .destructive) { wordToDelete = word }
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
            if model.motion.status == .streaming {
                HeadStillnessIndicator(isMoving: model.capture.headIsMoving)
            }
            if let issue = model.lastTakeIssue {
                Label(issue.message + " It wasn’t saved.", icon: .warning)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.finishing)
            } else if let notice = model.trainingNotice {
                Label(notice, icon: .checkCircle)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.signal)
            }
            HStack(spacing: Theme.s3) {
                if model.motion.status != .streaming {
                    Label(model.motion.status.label, icon: .connect)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.finishing)
                }
                Label(sessionSummary, icon: .train)
                    .font(.hkCaption.monospacedDigit())
                    .foregroundStyle(Theme.ink2)
                    .help("A session is one sitting. Evaluate holds out each session in turn, so record every word again in a new session for a fair test.")
                Spacer()
                Button("New session", icon: .plus) { model.beginNewExperimentSession() }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Start a separate sitting, for example after taking your AirPods out and back in.")
            }
        }
        .padding(Theme.s6 - 4)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var sessionSummary: String {
        let takes = model.currentSessionTakeCount(condition: model.trainingCondition)
        let complete = model.completeSessionCount(condition: model.trainingCondition)
        return "This session: \(takes) \(takes == 1 ? "take" : "takes"), \(complete) complete \(complete == 1 ? "session" : "sessions")"
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
            "Keep your head still and mouth it without a sound while you hold capture or Control. Add a word “\(TemplateClassifier.restLabel)” so stray movement is ignored."
        }
    }

    @ViewBuilder
    private var takes: some View {
        if let word = model.selectedWord {
            let takes = model.templates(for: word, condition: model.trainingCondition).reversed()
            let flagged = model.flaggedTakes(for: word, condition: model.trainingCondition).count
            VStack(alignment: .leading, spacing: Theme.s3) {
                HStack(spacing: Theme.s3) {
                    Text("Takes").font(.hkTitle3)
                    Text(flagged > 0 ? "\(takes.count - flagged) used, \(flagged) not used" : "\(takes.count)")
                        .font(.hkCallout.monospacedDigit())
                        .foregroundStyle(Theme.ink3)
                    Spacer()
                    if flagged > 0 {
                        Button("Remove \(flagged) flagged", icon: .trash) {
                            model.removeFlaggedTakes(for: word, condition: model.trainingCondition)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("These takes are too short, too long, or your head moved. They aren’t used for matching.")
                    }
                }
                if takes.isEmpty {
                    EmptyState(icon: .waveform, title: "No takes yet",
                               message: "Hold capture and mouth “\(word)”. Each take appears here.")
                        .card(padding: 0, style: .outlined)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.s3)], spacing: Theme.s3) {
                        ForEach(Array(takes)) { take in
                            TakeTile(template: take, isNew: take.id == model.lastTemplateID,
                                     issue: model.takeIssue(of: take)) {
                                model.deleteTemplate(take.id)
                            }
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .animation(Theme.gentle, value: takes.count)
                }
            }
        } else {
            EmptyState(icon: .plus, title: "Start with a word",
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
    var onDelete: () -> Void
    @State private var hovering = false

    private let goal = AppModel.takesPerWord

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(word).font(.hkBody.weight(isSelected ? .semibold : .regular))
                    if word == TemplateClassifier.restLabel {
                        Text("ignored")
                            .font(.hkMeta)
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    Group {
                        if count >= goal {
                            Glyph(.checkCircle).foregroundStyle(Theme.signal)
                        } else {
                            Text("\(count)/\(goal)")
                                .font(.hkCaption.monospacedDigit())
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                    .opacity(hovering ? 0 : 1)
                }
                .frame(height: 22)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline)
                        Capsule().fill(Theme.signal)
                            .frame(width: geo.size.width * min(CGFloat(count), CGFloat(goal)) / CGFloat(goal))
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
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button("Delete “\(word)”", icon: .trash, action: onDelete)
                    .buttonStyle(IconButtonStyle())
                    .padding(.trailing, Theme.s2)
                    .padding(.top, 3)
            }
        }
        .onHover { hovering = $0 }
        .animation(Theme.gentle, value: count)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct TakeTile: View {
    var template: Template
    var isNew: Bool
    var issue: TakeIssue?
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SignalPlot(title: "", samples: template.samples, channels: SignalPlot.rotation,
                       minScale: 0.05, height: 44, showsHeader: false)
                .opacity(issue == nil ? 1 : 0.5)
            HStack {
                if let issue {
                    Label(issue.label, icon: .warning)
                        .font(.hkMeta)
                        .foregroundStyle(Theme.finishing)
                        .help(issue.message)
                } else {
                    Text(String(format: "%.2f s, %d samples", template.duration, template.samples.count))
                        .font(.hkMeta.monospacedDigit())
                        .foregroundStyle(Theme.ink2)
                }
                Spacer()
                Button("Delete", icon: .trash, action: onDelete)
                    .buttonStyle(IconButtonStyle())
                    .opacity(hovering ? 1 : 0)
            }
        }
        .padding(Theme.s2 + 2)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
            .strokeBorder(isNew ? Theme.signal : issue != nil ? Theme.finishing.opacity(0.6) : Theme.hairline,
                          lineWidth: isNew ? 1.5 : 1))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
