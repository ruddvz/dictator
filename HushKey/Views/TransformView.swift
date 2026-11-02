import AppKit
import SwiftUI

private struct WritingStyleEditorRequest: Identifiable {
    var id = UUID()
    var preset: WritingStylePreset?
}

struct TransformView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedAction: LocalWritingTransform = .polish
    @State private var selectedStyleID: UUID?
    @State private var customStyles = WritingStylePresetStore.load()
    @State private var previewAction: LocalWritingTransform?
    @State private var previewLabel: String?
    @State private var draft = ""
    @State private var sourceSnapshot = ""
    @State private var errorTitle = "Couldn’t create a preview"
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var styleEditorRequest: WritingStyleEditorRequest?
    @State private var stylePendingDeletion: WritingStylePreset?

    private var currentText: String { model.transcriber.text }
    private var isBusy: Bool { model.audio.isRunning || model.isFinalizingDictation || model.transcriber.isFinalizing }
    private var selectedStyle: WritingStylePreset? {
        customStyles.first { $0.id == selectedStyleID }
    }
    private var normalizedSourceSnapshot: String {
        sourceSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canGenerate: Bool {
        let requiresLanguageModel = selectedStyle != nil || selectedAction.requiresLanguageModel
        return !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !model.localTransformService.isTransforming &&
            (!requiresLanguageModel || model.localTransformService.modelIsAvailable)
    }
    private var canApplyPreview: Bool {
        !normalizedDraft.isEmpty &&
            !sourceSnapshot.isEmpty && currentText == sourceSnapshot &&
            normalizedDraft != normalizedSourceSnapshot && !isBusy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "LOCAL WRITING TOOLS",
                    title: "Make it read like you",
                    subtitle: "Preview a change to your transcript or selected text, then choose whether to use it. Originals stay available until you apply a change.")

                selectedTextEditCard
                transcriptCard
                transformPicker
                if !draft.isEmpty { previewCard }
                if model.canUndoLocalTransform { undoCard }

                Label("Text transforms use Apple’s on-device Foundation Model when it is available. HushKey has no cloud fallback, and generated text is always shown for review before it replaces your transcript.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .alert(errorTitle, isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .sheet(item: $styleEditorRequest) { request in
            WritingStylePresetEditor(preset: request.preset) { name, instructions in
                saveStyle(name: name, instructions: instructions, editing: request.preset)
            }
        }
        .confirmationDialog("Delete this writing style?", isPresented: Binding(
            get: { stylePendingDeletion != nil }, set: { if !$0 { stylePendingDeletion = nil } }),
            titleVisibility: .visible) {
            Button("Delete style", role: .destructive) {
                if let stylePendingDeletion { deleteStyle(stylePendingDeletion) }
                stylePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { stylePendingDeletion = nil }
        } message: {
            Text("This removes the style from this Mac. It does not change any transcripts.")
        }
        .onChange(of: currentText) { oldText, newText in
            guard oldText != newText else { return }
            invalidatePreviewForTranscriptChange()
        }
    }

    private var selectedTextEditCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if model.selectedTextEditOriginal.isEmpty {
                    Text("Select text in another app, then hold \(model.selectedTextEditShortcut.label) and say what you want changed. The selected text stays on this Mac and is only read for that shortcut.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.insertion.isEnabled {
                        Button("Enable safe text access…") { model.screen = .settings }
                            .buttonStyle(.link)
                    }
                } else {
                    HStack {
                        Label("Selection from \(model.selectedTextEditTargetName ?? "another app")", systemImage: "text.cursor")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(model.selectedTextEditApplied ? "Done" : "Discard", systemImage: "xmark") {
                            model.clearSelectedTextEdit()
                        }
                            .disabled(model.isSelectedTextEditCapturing || model.isFinalizingSelectedTextEdit || model.isApplyingSelectedTextEdit)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Original selection").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(model.selectedTextEditOriginal)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.isSelectedTextEditCapturing ? "Live edit instruction" : "Edit instruction")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if model.isSelectedTextEditCapturing {
                            Text(model.selectedTextEditLiveInstruction.isEmpty
                                 ? "Listening…"
                                 : model.selectedTextEditLiveInstruction)
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        } else {
                            TextEditor(text: Binding(
                                get: { model.selectedTextEditInstruction },
                                set: { model.updateSelectedTextEditInstruction($0) }))
                                .font(.body)
                                .frame(minHeight: 75, maxHeight: 120)
                                .disabled(model.isFinalizingSelectedTextEdit || model.isGeneratingSelectedTextEdit || model.isApplyingSelectedTextEdit)
                                .padding(4)
                                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await model.previewSelectedTextEdit() }
                        } label: {
                            Label(model.isGeneratingSelectedTextEdit ? "Creating preview…" : "Preview edit",
                                  systemImage: model.isGeneratingSelectedTextEdit ? "hourglass" : "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canPreviewSelectedTextEdit)

                        if !model.selectedTextEditDraft.isEmpty {
                            if model.selectedTextEditApplied {
                                Label("Applied once · undo with ⌥⇧U in the target field", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Apply to \(model.selectedTextEditTargetName ?? "original app")",
                                       systemImage: "text.insert") {
                                    Task { await model.applySelectedTextEdit() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!model.canApplySelectedTextEdit)
                            }
                        }
                    }

                    if !model.selectedTextEditDraft.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Preview · review before applying").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            TextEditor(text: Binding(
                                get: { model.selectedTextEditDraft },
                                set: { model.updateSelectedTextEditDraft($0) }))
                                .font(.body)
                                .frame(minHeight: 90, maxHeight: 180)
                                .disabled(model.isApplyingSelectedTextEdit || model.selectedTextEditApplied)
                                .padding(4)
                                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    if let status = model.selectedTextEditStatus {
                        Label(status, systemImage: model.selectedTextEditApplied ? "checkmark.circle" : "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !model.localTransformService.modelIsAvailable {
                    Label(model.localTransformService.availabilityMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(model.selectedTextEditShortcutStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Requires Accessibility insertion to be enabled. HushKey uses the selected text and your spoken instruction for an on-device preview; neither is added to dictation history or sent to a server. Apply rechecks the original app, field, text, and selection.",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        } label: {
            Label("Voice edit selected text", systemImage: "text.cursor")
        }
    }

    private var transcriptCard: some View {
        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if currentText.isEmpty {
                    ContentUnavailableView(
                        "No transcript to transform",
                        systemImage: "text.alignleft",
                        description: Text("Start or restore a dictation first. Your transcript will appear here for review."))
                        .frame(minHeight: 140)
                } else {
                    TextEditor(text: transcriptBinding)
                        .font(.body)
                        .frame(minHeight: 150)
                        .disabled(isBusy)
                        .padding(4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Text("\(currentText.count.formatted()) characters")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Dictation", systemImage: "arrow.up.right") {
                            model.screen = .dictation
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .padding(10)
        } label: {
            Label("Current transcript", systemImage: "text.bubble")
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { model.transcriber.text }, set: { model.editCurrentDictation($0) })
    }

    private var transformPicker: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(LocalWritingTransform.allCases) { action in
                        Button {
                            selectedAction = action
                            selectedStyleID = nil
                            clearPreview()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: action.symbol)
                                    .font(.title3)
                                    .foregroundStyle(selectedStyle == nil && selectedAction == action ? Color.accentColor : Color.secondary)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.rawValue).font(.headline)
                                    Text(action.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .padding(12)
                            .background(selectedStyle == nil && selectedAction == action ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedStyle == nil && selectedAction == action ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.localTransformService.isTransforming)
                    }
                }

                customStylesSection

                if selectedStyle != nil || selectedAction.requiresLanguageModel {
                    Label(model.localTransformService.availabilityMessage,
                          systemImage: model.localTransformService.modelIsAvailable ? "checkmark.circle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("This cleanup runs locally with text rules and does not need a language model.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        Task { await createPreview() }
                    } label: {
                        Label(model.localTransformService.isTransforming ? "Working on this Mac…" : "Preview transform",
                              systemImage: model.localTransformService.isTransforming ? "hourglass" : "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerate)

                    if let statusMessage {
                        Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(10)
        } label: {
            Label("Choose a transformation", systemImage: "wand.and.stars")
        }
    }

    private var customStylesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Your writing styles", systemImage: "textformat")
                    .font(.headline)
                Spacer()
                Text("\(customStyles.count)/\(WritingStylePreset.maximumCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Add style", systemImage: "plus") {
                    styleEditorRequest = WritingStyleEditorRequest(preset: nil)
                }
                .disabled(customStyles.count >= WritingStylePreset.maximumCount || model.localTransformService.isTransforming)
            }

            if customStyles.isEmpty {
                Text("Create a style for a tone, format, or translation. It will run locally and appear here next time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(customStyles) { style in
                    HStack(spacing: 8) {
                        Button {
                            selectedStyleID = style.id
                            clearPreview()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "textformat")
                                    .foregroundStyle(selectedStyleID == style.id ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(style.name).font(.subheadline.weight(.semibold))
                                    Text(style.instructions).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(selectedStyleID == style.id ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .stroke(selectedStyleID == style.id ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.localTransformService.isTransforming)

                        Menu {
                            Button("Edit style", systemImage: "pencil") {
                                styleEditorRequest = WritingStyleEditorRequest(preset: style)
                            }
                            Button("Delete style", systemImage: "trash", role: .destructive) {
                                stylePendingDeletion = style
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 40)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(model.localTransformService.isTransforming)
                        .help("Edit or delete \(style.name)")
                    }
                }
            }
            Text("Styles are saved on this Mac. The selected instruction and transcript are sent only to Apple’s on-device model; HushKey has no cloud fallback.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var previewCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 180)
                    .padding(4)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                if normalizedDraft == normalizedSourceSnapshot {
                    Label("This preview matches your transcript; there is nothing to apply.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if sourceSnapshot != currentText {
                    Label("The transcript changed after this preview. Generate a fresh preview before applying it.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    Button("Copy preview", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft, forType: .string)
                        statusMessage = "Preview copied."
                    }
                    .buttonStyle(.bordered)

                    Button("Apply to Dictation", systemImage: "checkmark") {
                        guard model.applyLocalTransform(draft, basedOn: sourceSnapshot) else {
                            statusMessage = currentText == sourceSnapshot
                                ? "The transcript could not be updated. Try again."
                                : "The transcript changed. Create a fresh preview before applying."
                            return
                        }
                        sourceSnapshot = ""
                        draft = ""
                        previewAction = nil
                        previewLabel = nil
                        statusMessage = "Applied. You can undo this transform below."
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApplyPreview)
                }
            }
            .padding(10)
        } label: {
            Label("Review preview · \(previewLabel ?? (previewAction ?? selectedAction).rawValue)", systemImage: "doc.text.magnifyingglass")
        }
    }

    private var undoCard: some View {
        GroupBox {
            HStack {
                Label("The last local transform can be undone.", systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Undo transform", systemImage: "arrow.uturn.backward") {
                    model.undoLocalTransform()
                    draft = ""
                    sourceSnapshot = ""
                    previewAction = nil
                    previewLabel = nil
                    statusMessage = "Previous transcript restored."
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
        }
    }

    private func invalidatePreviewForTranscriptChange() {
        guard !sourceSnapshot.isEmpty || !draft.isEmpty else { return }
        draft = ""
        sourceSnapshot = ""
        previewAction = nil
        previewLabel = nil
        statusMessage = "The transcript changed. Create a fresh preview before applying."
    }

    @MainActor
    private func createPreview() async {
        let source = currentText
        let action = selectedAction
        let style = selectedStyle
        sourceSnapshot = source
        draft = ""
        errorTitle = "Couldn’t create a preview"
        errorMessage = nil
        statusMessage = nil
        do {
            let result: String
            if let style {
                result = try await model.localTransformService.transform(source, using: style)
            } else {
                result = try await model.localTransformService.transform(source, using: action)
            }
            guard selectedAction == action, selectedStyle == style, currentText == source else { return }
            previewAction = style == nil ? action : nil
            previewLabel = style?.name ?? action.rawValue
            draft = result
        } catch {
            sourceSnapshot = ""
            errorMessage = error.localizedDescription
        }
    }

    private func clearPreview() {
        previewAction = nil
        previewLabel = nil
        draft = ""
        sourceSnapshot = ""
        statusMessage = nil
    }

    private func saveStyle(name: String, instructions: String, editing: WritingStylePreset?) -> String? {
        if let issue = WritingStylePreset.validationIssue(name: name, instructions: instructions) { return issue }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !customStyles.contains(where: {
            $0.id != editing?.id && $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return "A style with that name already exists." }
        guard editing != nil || customStyles.count < WritingStylePreset.maximumCount else {
            return "You can save up to \(WritingStylePreset.maximumCount) writing styles."
        }

        var updated = customStyles
        let preset = WritingStylePreset(id: editing?.id ?? UUID(), name: cleanName,
                                        instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines))
        if let index = updated.firstIndex(where: { $0.id == preset.id }) { updated[index] = preset }
        else { updated.append(preset) }
        do {
            try WritingStylePresetStore.save(updated)
            customStyles = updated
            selectedStyleID = preset.id
            clearPreview()
            return nil
        } catch {
            return "Couldn’t save this style: \(error.localizedDescription)"
        }
    }

    private func deleteStyle(_ style: WritingStylePreset) {
        let updated = customStyles.filter { $0.id != style.id }
        do {
            try WritingStylePresetStore.save(updated)
            customStyles = updated
            if selectedStyleID == style.id { selectedStyleID = nil }
            clearPreview()
        } catch {
            errorTitle = "Couldn’t delete style"
            errorMessage = "Couldn’t delete this style: \(error.localizedDescription)"
        }
    }
}

private struct WritingStylePresetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var instructions: String
    @State private var validationMessage: String?
    let onSave: (String, String) -> String?

    init(preset: WritingStylePreset?, onSave: @escaping (String, String) -> String?) {
        _name = State(initialValue: preset?.name ?? "")
        _instructions = State(initialValue: preset?.instructions ?? "")
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name.isEmpty ? "New writing style" : "Edit writing style")
                .font(.title2.weight(.semibold))
            TextField("Name, for example: Warm and concise", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Writing style name")
            VStack(alignment: .leading, spacing: 6) {
                Text("Instruction").font(.headline)
                TextEditor(text: $instructions)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary, lineWidth: 1))
                    .accessibilityLabel("Writing style instruction")
                Text("Describe the tone or format. Example: Translate into French, keep product names unchanged, and return only the translation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let validationMessage {
                Text(validationMessage).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("Up to 32 characters for the name and 500 for the instruction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save style") {
                    validationMessage = onSave(name, instructions)
                    if validationMessage == nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 540)
    }
}
