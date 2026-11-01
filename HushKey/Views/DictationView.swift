import SwiftUI

struct DictationView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClearHistory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "VOICE · ON-DEVICE",
                    title: "Dictate anywhere",
                    subtitle: "Speak normally or whisper softly. HushKey transcribes on this Mac, then lets you review, copy, or insert the words into the app you’re using.")

                dictationCard
                Label("On-device recognition · Transcript history stays on this Mac when enabled · Microphone audio is not saved during dictation",
                      systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                transcriptCard
                historyCard
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var dictationCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: model.audio.isRunning ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 42, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(model.audio.isRunning ? Color.red : Color.accentColor)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.audio.isRunning ? "Listening" : "Ready when you are")
                            .font(.title3.weight(.semibold))
                        Text(model.audio.isRunning
                             ? "Your speech is being recognized locally. Select Stop when you’re done."
                             : "Your microphone is off until you start a dictation.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if model.audio.isRunning {
                        Circle().fill(.red).frame(width: 9, height: 9)
                        Text("LIVE").font(.caption.weight(.bold)).foregroundStyle(.red)
                    }
                }

                LevelMeter(value: Double(model.audio.level), tint: model.audio.isRunning ? .red : .blue)
                    .frame(height: 10)

                HStack(spacing: 10) {
                    Button {
                        Task { await model.toggleDictation() }
                    } label: {
                        Label(model.audio.isRunning ? "Stop dictation" : "Start dictation",
                              systemImage: model.audio.isRunning ? "stop.fill" : "mic.fill")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.audio.isRunning ? .red : .accentColor)
                    .controlSize(.large)

                    if model.audio.isRunning {
                        Text(model.audio.activeDeviceName ?? "Default microphone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Shortcut  \(model.dictationShortcut.label)")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                    }
                    Spacer()
                    Button("Microphone settings…") { model.screen = .settings }
                        .buttonStyle(.link)
                }

                if let error = model.audio.error ?? model.transcriber.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(model.dictationShortcutStatus, systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
        }
    }

    private var transcriptCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Transcript").font(.headline)
                    Spacer()
                    if !model.transcriber.text.isEmpty {
                        Button("Clear") { model.transcriber.clear() }
                            .disabled(model.audio.isRunning)
                    }
                }

                if model.transcriber.isRunning {
                    ScrollView {
                        Text(model.transcriber.text.isEmpty ? "Your words will appear here…" : model.transcriber.text)
                            .foregroundStyle(model.transcriber.text.isEmpty ? .tertiary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(minHeight: 140, maxHeight: 220)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    TextEditor(text: transcriptBinding)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 130, maxHeight: 220)
                        .padding(4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topLeading) {
                            if model.transcriber.text.isEmpty {
                                Text("Your transcript will appear here. You can edit it before inserting.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                HStack(spacing: 10) {
                    Button("Copy text", systemImage: "doc.on.doc") { model.copyDictationText() }
                        .disabled(model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Insert into current app", systemImage: "text.insert") { model.insertDictationText() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.insertion.isEnabled || model.audio.isRunning ||
                                  model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !model.insertion.isEnabled {
                        Button("Enable insertion…") { model.screen = .settings }
                            .buttonStyle(.link)
                    }
                }

                if !model.insertion.status.isEmpty {
                    Text(model.insertion.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
        }
    }

    private var historyCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent dictations").font(.headline)
                    Spacer()
                    Button("Clear history…", role: .destructive) { confirmClearHistory = true }
                        .disabled(model.dictationHistory.isEmpty)
                }
                if model.dictationHistory.isEmpty {
                    ContentUnavailableView(
                        "No dictations yet",
                        systemImage: "text.bubble",
                        description: Text(model.savesDictationHistory
                                          ? "Stopped dictations will appear here and stay on this Mac."
                                          : "Transcript history is off. Turn it on in Settings & Data to keep recent text."))
                        .frame(minHeight: 90)
                } else {
                    ForEach(model.dictationHistory.prefix(8)) { entry in
                        Button {
                            model.restoreDictation(entry)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.text).lineLimit(1).foregroundStyle(.primary)
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if entry.id != model.dictationHistory.prefix(8).last?.id { Divider() }
                    }
                }
                Text("Transcript history is stored in HushKey’s local Application Support folder while history is enabled. Microphone audio is not saved by dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .confirmationDialog("Delete all recent dictations?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) { model.clearDictationHistory() }
        }
    }

    private var transcriptBinding: Binding<String> {
        Binding(get: { model.transcriber.text }, set: { model.transcriber.replaceText($0) })
    }
}
