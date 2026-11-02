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
            VStack(alignment: .leading, spacing: Theme.s6) {
                PageHeader(eyebrow: "", title: "Transforms",
                           subtitle: "Rewrite a transcript or selected text on this Mac. You always see the result first.") {
                    Button("New style", systemImage: "plus") {
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

                Label("Runs on Apple’s on-device model. No cloud fallback.", systemImage: "lock.shield")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink3)
            }
            .pageLayout()
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
        .onAppear { syncAutomaticProfileStyle() }
        .onChange(of: model.dictationResultGeneration) { _, _ in syncAutomaticProfileStyle() }
    }

    private var selectedTextEditCard: some View {
        SettingsGroup(title: "Edit selected text by voice") {
            if model.selectedTextEditOriginal.isEmpty {
                SettingsRow(title: "Select text anywhere, hold the shortcut, say the change",
                            detail: model.insertion.isEnabled ? model.selectedTextEditShortcutStatus
                                : "Needs “Type where your cursor is” in Settings → Insertion.") {
                    if model.insertion.isEnabled {
                        KeycapShortcut(label: model.selectedTextEditShortcut.label, size: 13)
                    } else {
                        Button("Turn on") {
                            UserDefaults.standard.set(SettingsView.Section.insertion.rawValue, forKey: "settingsSection")
                            model.screen = .settings
                        }
                        .buttonStyle(SecondaryButtonStyle(minWidth: 96))
                    }
                }
            } else {
            GroupRow {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    HStack {
                        Label("Selection from \(model.selectedTextEditTargetName ?? "another app")", systemImage: "text.cursor")
                            .font(.hkCallout.weight(.semibold))
                        Spacer()
                        Button(model.selectedTextEditApplied ? "Done" : "Discard", systemImage: "xmark") {
                            model.clearSelectedTextEdit()
                        }
                            .disabled(model.isSelectedTextEditCapturing || model.isFinalizingSelectedTextEdit || model.isApplyingSelectedTextEdit)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Original selection").font(.hkCaption.weight(.semibold)).foregroundStyle(Theme.ink2)
                        Text(model.selectedTextEditOriginal)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.isSelectedTextEditCapturing ? "Live edit instruction" : "Edit instruction")
                            .font(.hkCaption.weight(.semibold)).foregroundStyle(Theme.ink2)
                        if model.isSelectedTextEditCapturing {
                            Text(model.selectedTextEditLiveInstruction.isEmpty
                                 ? "Listening…"
                                 : model.selectedTextEditLiveInstruction)
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                                .padding(10)
                                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 8))
                        } else {
                            TextEditor(text: Binding(
                                get: { model.selectedTextEditInstruction },
                                set: { model.updateSelectedTextEditInstruction($0) }))
                                .font(.hkBody)
                                .frame(minHeight: 75, maxHeight: 120)
                                .disabled(model.isFinalizingSelectedTextEdit || model.isGeneratingSelectedTextEdit || model.isApplyingSelectedTextEdit)
                                .padding(4)
                                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r3, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await model.previewSelectedTextEdit() }
                        } label: {
                            Label(model.isGeneratingSelectedTextEdit ? "Creating preview…" : "Preview edit",
                                  systemImage: model.isGeneratingSelectedTextEdit ? "hourglass" : "sparkles")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!model.canPreviewSelectedTextEdit)

                        if !model.selectedTextEditDraft.isEmpty {
                            if model.selectedTextEditApplied {
                                Label("Applied once · undo with ⌥⇧U in the target field", systemImage: "checkmark.circle")
                                    .font(.hkCaption)
                                    .foregroundStyle(Theme.ink2)
                            } else {
                                Button("Apply to \(model.selectedTextEditTargetName ?? "original app")",
                                       systemImage: "text.insert") {
                                    Task { await model.applySelectedTextEdit() }
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(!model.canApplySelectedTextEdit)
                            }
                        }
                    }

                    if !model.selectedTextEditDraft.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Preview · review before applying").font(.hkCaption.weight(.semibold)).foregroundStyle(Theme.ink2)
                            TextEditor(text: Binding(
                                get: { model.selectedTextEditDraft },
                                set: { model.updateSelectedTextEditDraft($0) }))
                                .font(.hkBody)
                                .frame(minHeight: 90, maxHeight: 180)
                                .disabled(model.isApplyingSelectedTextEdit || model.selectedTextEditApplied)
                                .padding(4)
                                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r3, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                    }

                    if let status = model.selectedTextEditStatus {
                        Label(status, systemImage: model.selectedTextEditApplied ? "checkmark.circle" : "info.circle")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !model.localTransformService.modelIsAvailable {
                    Label(model.localTransformService.availabilityMessage, systemImage: "info.circle")
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
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Your text").font(.hkTitle3)
                Spacer()
                if !currentText.isEmpty {
                    Text("\(currentText.count.formatted()) characters")
                        .font(.hkMeta.monospacedDigit())
                        .foregroundStyle(Theme.ink3)
                }
            }
            if currentText.isEmpty {
                EmptyState(systemImage: "text.alignleft", title: "Nothing to transform yet",
                           message: "Dictate something, or pick a dictation from history to edit it again.") {
                    Button("Go to Dictation") { model.screen = .dictation }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .card(padding: 0, style: .outlined)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: transcriptBinding)
                        .font(.hkBody)
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140, maxHeight: 260)
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
                                  systemImage: model.localTransformService.isTransforming ? "hourglass" : "sparkles")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canGenerate)
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.vertical, Theme.s3)
                }
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
            }
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { model.transcriber.text }, set: { model.editCurrentDictation($0) })
    }

    /// Wispr-style card grid: built-in transforms, then your styles, then a "create" card.
    private var transformPicker: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Choose a transform").font(.hkTitle3)
                Spacer()
                Text("\(model.writingStylePresets.count)/\(WritingStylePreset.maximumCount) styles")
                    .font(.hkMeta.monospacedDigit())
                    .foregroundStyle(Theme.ink3)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.s3), count: 3),
                      alignment: .leading, spacing: Theme.s3) {
                ForEach(LocalWritingTransform.allCases) { action in
                    TransformCard(symbol: action.symbol, title: action.rawValue, detail: action.description,
                                  badge: action.requiresLanguageModel ? "Model" : "Instant",
                                  isSelected: selectedStyle == nil && selectedAction == action) {
                        selectedAction = action
                        selectedStyleID = nil
                        selectedStyleCameFromProfile = false
                        clearPreview()
                    }
                    .disabled(model.localTransformService.isTransforming)
                }
                ForEach(model.writingStylePresets) { style in
                    TransformCard(symbol: "textformat", title: style.name, detail: style.instructions,
                                  badge: "Your style", isSelected: selectedStyleID == style.id) {
                        selectedStyleID = style.id
                        selectedStyleCameFromProfile = false
                        clearPreview()
                    }
                    .disabled(model.localTransformService.isTransforming)
                    .contextMenu {
                        Button("Edit style", systemImage: "pencil") {
                            styleEditorRequest = WritingStyleEditorRequest(preset: style)
                        }
                        Button("Delete style", systemImage: "trash", role: .destructive) {
                            stylePendingDeletion = style
                        }
                    }
                }
                if model.writingStylePresets.count < WritingStylePreset.maximumCount {
                    Button {
                        styleEditorRequest = WritingStyleEditorRequest(preset: nil)
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.s2) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(Theme.well, in: Circle())
                            Spacer(minLength: Theme.s2)
                            Text("Create your own").font(.hkHeadline)
                            Text("A tone, format or translation you reuse.")
                                .font(.hkCaption)
                                .foregroundStyle(Theme.ink2)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                        .padding(Theme.s4)
                        .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.localTransformService.isTransforming)
                }
            }
            if !model.writingStylePresets.isEmpty {
                Text("Right-click a style to edit or delete it.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink3)
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text("Preview").font(.hkTitle3)
                Text(previewLabel ?? (previewAction ?? selectedAction).rawValue)
                    .font(.hkCallout)
                    .foregroundStyle(Theme.ink2)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $draft)
                    .font(.hkBody)
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(Theme.s3)
                RowDivider()
                HStack(spacing: Theme.s2) {
                    if sourceSnapshot != currentText {
                        Label("Your text changed. Preview again.", systemImage: "exclamationmark.triangle")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.finishing)
                    } else if normalizedDraft == normalizedSourceSnapshot {
                        Label("Same as your text.", systemImage: "checkmark.circle")
                            .font(.hkCaption)
                            .foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft, forType: .string)
                        statusMessage = "Preview copied."
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Use this", systemImage: "checkmark") {
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
                .padding(.horizontal, Theme.s4)
                .padding(.vertical, Theme.s3)
            }
            .background(Theme.signalSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(Theme.signal.opacity(0.35), lineWidth: 1))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var undoCard: some View {
        SettingsGroup {
            SettingsRow(title: "Undo the last transform", detail: "Puts your previous text back.") {
                Button("Undo", systemImage: "arrow.uturn.backward") {
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
        }) else { return "A style with that name already exists." }
        guard editing != nil || model.writingStylePresets.count < WritingStylePreset.maximumCount else {
            return "You can save up to \(WritingStylePreset.maximumCount) writing styles."
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
            return "Couldn’t save this style: \(error.localizedDescription)"
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
                .font(.hkTitle2.weight(.semibold))
            TextField("Name, for example: Warm and concise", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Writing style name")
            VStack(alignment: .leading, spacing: 6) {
                Text("Instruction").font(.hkHeadline)
                TextEditor(text: $instructions)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary, lineWidth: 1))
                    .accessibilityLabel("Writing style instruction")
                Text("Describe the tone or format. Example: Translate into French, keep product names unchanged, and return only the translation.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
            }
            if let validationMessage {
                Text(validationMessage).font(.hkCaption).foregroundStyle(Theme.finishing)
            }
            HStack {
                Text("Up to 32 characters for the name and 500 for the instruction.")
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save style") {
                    validationMessage = onSave(name, instructions)
                    if validationMessage == nil { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 540)
    }
}

/// One transform choice, laid out like Wispr's transform cards: badge, title, short description.
private struct TransformCard: View {
    var symbol: String
    var title: String
    var detail: String
    var badge: String
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.s2) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.signal : Theme.ink2)
                        .frame(width: 28, height: 28)
                        .background(isSelected ? Theme.sheet : Theme.well,
                                    in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
                    Spacer()
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Theme.well, in: Capsule())
                }
                Spacer(minLength: Theme.s2)
                Text(title).font(.hkHeadline).foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(Theme.s4)
            .background(isSelected ? Theme.signalSoft : hovering ? Theme.well : Theme.sheet,
                        in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(isSelected ? Theme.signal : Theme.hairline, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: isSelected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
