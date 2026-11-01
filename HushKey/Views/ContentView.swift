import AVFoundation
import Speech
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    private static let labScreens: [AppModel.Screen] = [.setup, .train, .evaluate, .use]

    var body: some View {
        NavigationSplitView {
            List(selection: screenSelection) {
                Section("WRITE") {
                    Label(AppModel.Screen.dictation.rawValue, systemImage: AppModel.Screen.dictation.symbol)
                        .tag(AppModel.Screen.dictation)
                    Label(AppModel.Screen.transforms.rawValue, systemImage: AppModel.Screen.transforms.symbol)
                        .tag(AppModel.Screen.transforms)
                    Label(AppModel.Screen.files.rawValue, systemImage: AppModel.Screen.files.symbol)
                        .tag(AppModel.Screen.files)
                }
                Section("SILENT LAB") {
                    ForEach(Self.labScreens) { screen in
                        Label(screen.rawValue, systemImage: screen.symbol).tag(screen)
                    }
                }
                Section("MANAGE") {
                    Label(AppModel.Screen.personalization.rawValue, systemImage: AppModel.Screen.personalization.symbol)
                        .tag(AppModel.Screen.personalization)
                    Label(AppModel.Screen.settings.rawValue, systemImage: AppModel.Screen.settings.symbol)
                        .tag(AppModel.Screen.settings)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) { brand }
            .safeAreaInset(edge: .bottom, spacing: 0) { SetupChecklist().padding(10) }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch model.screen {
            case .dictation: DictationView()
            case .transforms: TransformView()
            case .files: FileTranscriptionView()
            case .setup: SetupView()
            case .train: TrainView()
            case .evaluate: EvaluateView()
            case .use: UseView()
            case .personalization: PersonalizationView()
            case .settings: SettingsView()
            }
        }
        .toolbar {
            if Self.labScreens.contains(model.screen) {
                ToolbarItem(placement: .status) {
                    MotionStatusBadge(status: model.motion.status, rate: model.motion.sampleRate)
                }
            }
        }
        .navigationTitle(model.screen.rawValue)
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text("HushKey")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    private var screenSelection: Binding<AppModel.Screen?> {
        Binding(get: { model.screen }, set: { if let screen = $0 { model.screen = screen } })
    }
}

/// First-run steps for voice dictation. Hides itself once every step is done.
private struct SetupChecklist: View {
    @Environment(AppModel.self) private var model
    @State private var microphoneGranted = false
    @State private var speechGranted = false

    private struct Step: Identifiable {
        var id: String { title }
        var title: String
        var isDone: Bool
    }

    private var steps: [Step] {
        [
            Step(title: "Allow microphone", isDone: microphoneGranted),
            Step(title: "Allow speech recognition", isDone: speechGranted),
            Step(title: "Turn on text insertion", isDone: model.insertion.isEnabled),
            Step(title: "Try your first dictation", isDone: !model.dictationHistory.isEmpty),
        ]
    }

    var body: some View {
        let completed = steps.filter(\.isDone).count
        Group {
            if completed < steps.count {
                Button { model.screen = completed >= 2 ? .dictation : .settings } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Get started").font(.callout.weight(.semibold))
                            Spacer()
                            Text("\(completed)/\(steps.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(completed), total: Double(steps.count))
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                        ForEach(steps) { step in
                            Label {
                                Text(step.title)
                                    .foregroundStyle(step.isDone ? .secondary : .primary)
                                    .strikethrough(step.isDone, color: .secondary)
                            } icon: {
                                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.isDone ? Color.green : Color.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open the next setup step")
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: model.audio.isRunning) { _, _ in refresh() }
    }

    private func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }
}
