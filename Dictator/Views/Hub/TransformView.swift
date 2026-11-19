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
    @State private var selectedStyleCameFromProfile = false
    @State private var lastSynchronizedDictationGeneration: Int?
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
        model.writingStylePresets.first { $0.id == selectedStyleID }
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
            PageColumn {
                PageHeader(title: "Transforms",
                           subtitle: "Rewrite a transcript or selected text on this Mac. You always see the result first.") {
                    Button("New transform", icon: .plus) {
                        styleEditorRequest = WritingStyleEditorRequest(preset: nil)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.writingStylePresets.count >= WritingStylePreset.maximumCount || model.localTransformService.isTransforming)
                }

                transformPicker
                transcriptCard
                if !draft.isEmpty { previewCard }
                if model.canUndoLocalTransform { undoCard }
                selectedTextEditCard

                Text("Runs on Apple’s on-device model. No cloud fallback.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
            }
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
        .confirmationDialog("Delete this transform?", isPresented: Binding(
            get: { stylePendingDeletion != nil }, set: { if !$0 { stylePendingDeletion = nil } }),
            titleVisibility: .visible) {
            Button("Delete transform", role: .destructive) {
                if let stylePendingDeletion { deleteStyle(stylePendingDeletion) }
                stylePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { stylePendingDeletion = nil }
        } message: {
            Text("This removes the transform from this Mac. It does not change any transcripts.")
        }
        .onChange(of: currentText) { oldText, newText in
            guard oldText != newText else { return }
            invalidatePreviewForTranscriptChange()
        }
        .onAppear { syncAutomaticProfileStyle() }
        .onChange(of: model.dictationResultGeneration) { _, _ in syncAutomaticProfileStyle() }
    }

    private var selectedTextEditCard: some View {
        SettingsGroup(title: "Edit selected text by voice") {
            if model.selectedTextEditOriginal.isEmpty {
                SettingsRow(title: "Select text anywhere, hold the shortcut, say the change",
                            detail: model.insertion.isEnabled ? model.selectedTextEditShortcutStatus
                                : "Needs “Type where your cursor is” in Settings › Typing.") {
                    if model.insertion.isEnabled {
                        KeycapShortcut(label: model.selectedTextEditShortcut.label, size: 13)
                    } else {
                        Button("Turn on") {
                            UserDefaults.standard.set(SettingsView.Section.insertion.rawValue, forKey: "settingsSection")
                            model.screen = .settings
                        }
                        .buttonStyle(SecondaryButtonStyle(minWidth: Theme.buttonMinWidth))
                    }
                }
            } else {
            GroupRow {
            VStack(alignment: .leading, spacing: Theme.stackGap) {
                Group {
                    HStack {
                        Label("Selection from \(model.selectedTextEditTargetName ?? "another app")", icon: .cursor)
                            .font(.hkCallout.weight(.semibold))
                        Spacer()
                        Button(model.selectedTextEditApplied ? "Done" : "Discard", icon: .close) {
                            model.clearSelectedTextEdit()
                        }
                            .disabled(model.isSelectedTextEditCapturing || model.isFinalizingSelectedTextEdit || model.isApplyingSelectedTextEdit)
                    }

                    VStack(alignment: .leading, spacing: Theme.s1) {
                        Text("Original selection").font(.hkCaption.weight(.semibold)).foregroundStyle(Theme.ink2)
                        Text(model.selectedTextEditOriginal)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.s3)
                            .surface(.outlined, radius: Theme.controlRadius)
                    }

                    VStack(alignment: .leading, spacing: Theme.s1) {
                        Text(model.isSelectedTextEditCapturing ? "Live edit instruction" : "Edit instruction")
                            .font(.hkCaption.weight(.semibold)).foregroundStyle(Theme.ink2)
                        if model.isSelectedTextEditCapturing {
                            Text(model.selectedTextEditLiveInstruction.isEmpty
                                 ? "Listening…"
                                 : model.selectedTextEditLiveInstruction)
                                .frame(maxWidth: .infinity, minHeight: Theme.editorShort, alignment: .topLeading)
                                .padding(Theme.s3)
                                .surface(.outlined, radius: Theme.controlRadius)
                        } else {
                            TextEditor(text: Binding(
                                get: { model.selectedTextEditInstruction },
                                set: { model.updateSelectedTextEditInstruction($0) }))
                                .font(.hkBody)
                                .frame(minHeight: Theme.editorShort, maxHeight: Theme.editorShortMax)
                                .disabled(model.isFinalizingSelectedTextEdit || model.isGeneratingSelectedTextEdit || model.isApplyingSelectedTextEdit)
                                .editorField()
                        }
                    }

                    HStack(spacing: Theme.controlGap) {
                        Button {
                            Task { await model.previewSelectedTextEdit() }
                        } label: {
                            Label(model.isGeneratingSelectedTextEdit ? "Creating preview…" : "Preview edit",
                                  icon: model.isGeneratingSelectedTextEdit ? .clock : .sparkle)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!model.canPreviewSelectedTextEdit)

                        if !model.selectedTextEditDraft.isEmpty {
                            if model.selectedTextEditApplied {
                                Label("Applied once. Undo with ⌥⇧U in the target field.", icon: .checkCircle)
                                    .font(.hkCaption)
                                    .foregroundStyle(Theme.ink2)
                            } else {
                                Button("Apply to \(model.selectedTextEditTargetName ?? "original app")",
                                       icon: .insert) {
                                    Task { await model.applySelectedTextEdit() }
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(!model.canApplySelectedTextEdit)
                            }
                        }
                    }

                    if !model.selectedTextEditDraft.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.s1) {
                            Text("Preview, review before applying").font(.hkCaption.weight(.semibold)).foregroundStyle(Theme.ink2)
                            TextEditor(text: Binding(
                                get: { model.selectedTextEditDraft },
                                set: { model.updateSelectedTextEditDraft($0) }))
                                .font(.hkBody)
                                .frame(minHeight: Theme.editorShort, maxHeight: Theme.editorTall)
                                .disabled(model.isApplyingSelectedTextEdit || model.selectedTextEditApplied)
                                .editorField()
                        }
                    }

                    if let status = model.selectedTextEditStatus {
                        Label(status, icon: model.selectedTextEditApplied ? .checkCircle : .info)
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !model.localTransformService.modelIsAvailable {
                    Text(model.localTransformService.availabilityMessage)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
    }

    private var transcriptCard: some View {
        PageSection("Your text") {
            if !currentText.isEmpty {
                Text("\(currentText.count.formatted()) characters")
                    .font(.hkMeta.monospacedDigit())
                    .foregroundStyle(Theme.ink3)
            }
        } content: {
            if currentText.isEmpty {
                HStack(spacing: Theme.s4) {
                    Text("Dictate or pick a dictation from History to transform.")
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.s2)
                    Button("Go to Home") { model.screen = .dictation }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: transcriptBinding)
                        .font(.hkBody)
                        .lineSpacing(Theme.leading)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: Theme.editorMedium, maxHeight: Theme.editorTallMax)
                        .disabled(isBusy)
                        .padding(Theme.s3)
                    RowDivider()
                    HStack(spacing: Theme.s2) {
                        Text(selectedStyle?.name ?? selectedAction.rawValue)
                            .font(.hkCallout.weight(.medium))
                        Text(selectedStyle == nil && !selectedAction.requiresLanguageModel
                             ? "Text rules, instant"
                             : model.localTransformService.modelIsAvailable ? "On-device model" : model.localTransformService.availabilityMessage)
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                        Spacer()
                        if let statusMessage {
                            Text(statusMessage).font(.hkCaption).foregroundStyle(Theme.ink2).lineLimit(1)
                        }
                        Button {
                            Task { await createPreview() }
                        } label: {
                            Label(model.localTransformService.isTransforming ? "Working…" : "Preview",
                                  icon: model.localTransformService.isTransforming ? .clock : .sparkle)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canGenerate)
                    }
                    .padding(.horizontal, Theme.rowPaddingH)
                    .padding(.vertical, Theme.s3)
                }
                .surface(.outlined)
            }
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { model.transcriber.text }, set: { model.editCurrentDictation($0) })
    }

    /// One tile in the transform grid: a built-in transform or one of yours.
    private enum TransformChoice: Identifiable {
        case builtIn(LocalWritingTransform)
        case custom(WritingStylePreset)

        var id: String {
            switch self {
            case .builtIn(let action): "builtin-\(action.rawValue)"
            case .custom(let style): style.id.uuidString
            }
        }
    }

    private var transformChoices: [TransformChoice] {
        LocalWritingTransform.allCases.map(TransformChoice.builtIn) + model.writingStylePresets.map(TransformChoice.custom)
    }

    /// Card grid: built-in transforms, then your own. "New transform" in the header adds one.
    private var transformPicker: some View {
        PageSection("Choose a transform") {
            if !model.writingStylePresets.isEmpty {
                Text("\(model.writingStylePresets.count) of \(WritingStylePreset.maximumCount) custom")
                    .font(.hkCaption.monospacedDigit())
                    .foregroundStyle(Theme.ink2)
            }
        } content: {
            CardGrid(items: transformChoices) { choice in
                switch choice {
                case .builtIn(let action):
                    SelectableCard(title: action.rawValue,
                                   detail: action.requiresLanguageModel && !model.localTransformService.modelIsAvailable
                                       ? action.description + " Needs the on-device model."
                                       : action.description,
                                   symbol: action.symbol,
                                   isSelected: selectedStyle == nil && selectedAction == action,
                                   detailLines: 3) {
                        selectedAction = action
                        selectedStyleID = nil
                        selectedStyleCameFromProfile = false
                        clearPreview()
                    }
                    .disabled(model.localTransformService.isTransforming)
                case .custom(let style):
                    SelectableCard(title: style.name, detail: style.instructions, symbol: "textformat",
                                   isSelected: selectedStyleID == style.id, detailLines: 3) {
                        selectedStyleID = style.id
                        selectedStyleCameFromProfile = false
                        clearPreview()
                    }
                    .disabled(model.localTransformService.isTransforming)
                    .contextMenu {
                        Button("Edit transform", systemImage: "pencil") {
                            styleEditorRequest = WritingStyleEditorRequest(preset: style)
                        }
                        Button("Delete transform", systemImage: "trash", role: .destructive) {
                            stylePendingDeletion = style
                        }
                    }
                }
            }
            if !model.writingStylePresets.isEmpty {
                Text("Right-click a custom transform to edit or delete it.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    private var previewCard: some View {
        PageSection("Preview") {
            Text(previewLabel ?? (previewAction ?? selectedAction).rawValue)
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $draft)
                    .font(.hkBody)
                    .lineSpacing(Theme.leading)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: Theme.editorMedium)
                    .padding(Theme.s3)
                RowDivider()
                HStack(spacing: Theme.s2) {
                    if sourceSnapshot != currentText {
                        Label("Your text changed. Preview again.", icon: .warning)
                            .font(.hkCaption)
                            .foregroundStyle(Theme.finishing)
                    } else if normalizedDraft == normalizedSourceSnapshot {
                        Label("Same as your text.", icon: .checkCircle)
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    Button("Copy", icon: .copy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft, forType: .string)
                        statusMessage = "Preview copied."
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Use this", icon: .check) {
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
                        statusMessage = "Applied. You can undo it."
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canApplyPreview)
                }
                .padding(.horizontal, Theme.rowPaddingH)
                .padding(.vertical, Theme.s3)
            }
            .surface(.tinted)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var undoCard: some View {
        SettingsGroup {
            SettingsRow(title: "Undo the last transform", detail: "Puts your previous text back.") {
                Button("Undo", icon: .undo) {
                    model.undoLocalTransform()
                    draft = ""
                    sourceSnapshot = ""
                    previewAction = nil
                    previewLabel = nil
                    statusMessage = "Previous transcript restored."
                }
                .buttonStyle(SecondaryButtonStyle())
            }
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

    private func syncAutomaticProfileStyle() {
        let generation = model.dictationResultGeneration
        guard lastSynchronizedDictationGeneration != generation else { return }
        lastSynchronizedDictationGeneration = generation
        if model.activeDictationProfileName != nil, let requestedID = model.activeDictationWritingStylePresetID,
           model.writingStylePresets.contains(where: { $0.id == requestedID }) {
            selectedStyleID = requestedID
            selectedStyleCameFromProfile = true
        } else if selectedStyleCameFromProfile {
            selectedStyleID = nil
            selectedStyleCameFromProfile = false
        }
        clearPreview()
    }

    private func saveStyle(name: String, instructions: String, editing: WritingStylePreset?) -> String? {
        if let issue = WritingStylePreset.validationIssue(name: name, instructions: instructions) { return issue }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.writingStylePresets.contains(where: {
            $0.id != editing?.id && $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return "A transform with that name already exists." }
        guard editing != nil || model.writingStylePresets.count < WritingStylePreset.maximumCount else {
            return "You can save up to \(WritingStylePreset.maximumCount) custom transforms."
        }

        var updated = model.writingStylePresets
        let preset = WritingStylePreset(id: editing?.id ?? UUID(), name: cleanName,
                                        instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines))
        if let index = updated.firstIndex(where: { $0.id == preset.id }) { updated[index] = preset }
        else { updated.append(preset) }
        do {
            try model.saveWritingStylePresets(updated)
            selectedStyleID = preset.id
            selectedStyleCameFromProfile = false
            clearPreview()
            return nil
        } catch {
            return "Couldn’t save this transform: \(error.localizedDescription)"
        }
    }

    private func deleteStyle(_ style: WritingStylePreset) {
        let updated = model.writingStylePresets.filter { $0.id != style.id }
        do {
            try model.saveWritingStylePresets(updated)
            model.clearAppProfileStyleReference(style.id)
            if selectedStyleID == style.id {
                selectedStyleID = nil
                selectedStyleCameFromProfile = false
            }
            clearPreview()
        } catch {
            errorTitle = "Couldn’t delete transform"
            errorMessage = "Couldn’t delete this transform: \(error.localizedDescription)"
        }
    }
}

private struct WritingStylePresetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var instructions: String
    @State private var validationMessage: String?
    private let isNew: Bool
    let onSave: (String, String) -> String?

    init(preset: WritingStylePreset?, onSave: @escaping (String, String) -> String?) {
        isNew = preset == nil
        _name = State(initialValue: preset?.name ?? "")
        _instructions = State(initialValue: preset?.instructions ?? "")
        self.onSave = onSave
    }

    var body: some View {
        EditorSheet(title: isNew ? "New transform" : "Edit transform",
                    subtitle: "Rewrites text on this Mac with your instruction.",
                    note: "Name up to 32 characters, instruction up to 500.",
                    primaryTitle: isNew ? "Create" : "Save", canSave: canSave, onSave: save) {
            SheetField(label: "Name", prompt: "For example: Warm and concise", text: $name, autofocus: isNew)
            SheetField(label: "Instruction",
                       prompt: "Describe the tone or format",
                       text: $instructions,
                       hint: "For example: Translate into French and keep product names unchanged.",
                       multiline: true)
            if let validationMessage {
                SheetNotice(message: validationMessage)
            }
        }
        .animation(Theme.snappy, value: validationMessage)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        validationMessage = onSave(name, instructions)
        if validationMessage == nil { dismiss() }
    }
}
