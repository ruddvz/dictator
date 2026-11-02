import AppKit
import SwiftUI

struct TransformView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedAction: LocalWritingTransform = .polish
    @State private var previewAction: LocalWritingTransform?
    @State private var draft = ""
    @State private var sourceSnapshot = ""
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var currentText: String { model.transcriber.text }
    private var isBusy: Bool { model.audio.isRunning || model.isFinalizingDictation || model.transcriber.isFinalizing }
    private var normalizedSourceSnapshot: String {
        sourceSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canGenerate: Bool {
        !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !model.localTransformService.isTransforming &&
            (!selectedAction.requiresLanguageModel || model.localTransformService.modelIsAvailable)
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
                    subtitle: "Preview a change to your current transcript, then choose whether to use it. Your original recognition remains available to restore.")

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
            .pageLayout()
        }
        .alert("Couldn’t create a preview", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
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
        Binding(get: { model.transcriber.text }, set: { model.transcriber.replaceText($0) })
    }

    private var transformPicker: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(LocalWritingTransform.allCases) { action in
                        Button {
                            selectedAction = action
                            previewAction = nil
                            draft = ""
                            sourceSnapshot = ""
                            statusMessage = nil
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: action.symbol)
                                    .font(.title3)
                                    .foregroundStyle(selectedAction == action ? Theme.ink : Color.secondary)
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
                            .background(selectedAction == action ? Theme.ink.opacity(0.09) : Color(nsColor: .controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedAction == action ? Theme.ink.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.localTransformService.isTransforming)
                    }
                }

                if selectedAction.requiresLanguageModel {
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
                        statusMessage = "Applied. You can undo this transform below."
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApplyPreview)
                }
            }
            .padding(10)
        } label: {
            Label("Review preview · \((previewAction ?? selectedAction).rawValue)", systemImage: "doc.text.magnifyingglass")
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
                    statusMessage = "Previous transcript restored."
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
        }
    }

    @MainActor
    private func createPreview() async {
        let source = currentText
        let action = selectedAction
        sourceSnapshot = source
        draft = ""
        errorMessage = nil
        statusMessage = nil
        do {
            let result = try await model.localTransformService.transform(source, using: action)
            guard selectedAction == action else { return }
            previewAction = action
            draft = result
        } catch {
            sourceSnapshot = ""
            errorMessage = error.localizedDescription
        }
    }
}
