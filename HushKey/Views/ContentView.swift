import AVFoundation
import Speech
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .light

    static let labScreens: [AppModel.Screen] = [.setup, .train, .evaluate, .use]
    private static let mainScreens: [AppModel.Screen] = [.dictation, .insights, .style, .transforms, .files, .meetings, .personalization]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Theme.sidebarWidth)
            page
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                .padding([.top, .trailing, .bottom], Theme.s2)
        }
        .background(Theme.paper)
        .ignoresSafeArea()
        .foregroundStyle(Theme.ink)
        .font(.hkBody)
        .groupBoxStyle(CardGroupBoxStyle())
        .tint(Theme.ink)
        .preferredColorScheme(appearance.colorScheme)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 40) // clears the window controls
                .padding(.horizontal, Theme.s4)
                .padding(.bottom, Theme.s4)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s1) {
                    ForEach(Self.mainScreens) { SidebarRow(screen: $0) }
                    HStack {
                        SectionLabel(title: "Silent lab")
                        Spacer()
                        if model.motion.isConnected {
                            Circle().fill(Theme.success).frame(width: 6, height: 6)
                                .help(model.motion.status.label)
                        }
                    }
                    .padding(.horizontal, Theme.s3 - 2)
                    .padding(.top, Theme.s5)
                    .padding(.bottom, 2)
                    ForEach(Self.labScreens) { SidebarRow(screen: $0) }
                }
                .padding(.horizontal, Theme.s3)
            }
            .scrollIndicators(.never)

            VStack(alignment: .leading, spacing: Theme.s1) {
                SetupChecklist()
                    .padding(.bottom, Theme.s2)
                SidebarRow(screen: .settings)
            }
            .padding([.horizontal, .bottom], Theme.s3)
        }
    }

    private var brand: some View {
        HStack(spacing: Theme.s2) {
            MorphIcon(phase: model.audio.isRunning ? .listening
                      : (model.isFinalizingDictation || model.transcriber.isFinalizing) ? .working : .idle,
                      level: model.audio.level, lineWidth: 2.2)
                .frame(width: 22, height: 22)
                .foregroundStyle(model.audio.isRunning ? Theme.listening : Theme.ink)
            Text("HushKey")
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("HushKey")
    }

    // MARK: Page

    private var page: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch model.screen {
                case .dictation: DictationView()
                case .transforms: TransformView()
                case .files: FileTranscriptionView()
                case .meetings: MeetingNotesView()
                case .setup: SetupView()
                case .train: TrainView()
                case .evaluate: EvaluateView()
                case .use: UseView()
                case .personalization: PersonalizationView()
                case .style: StyleView()
                case .insights: InsightsView()
                case .settings: SettingsView()
                }
            }
            .id(model.screen)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if Self.labScreens.contains(model.screen) {
                MotionStatusBadge(status: model.motion.status, rate: model.motion.sampleRate)
                    .font(.system(size: 13))
                    .padding(.horizontal, Theme.s3)
                    .frame(height: 26)
                    .background(Theme.well, in: Capsule())
                    .padding(Theme.s4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.r1, style: .continuous))
        .animation(Theme.snappy, value: model.screen)
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    static let storageKey = "appearance"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Sidebar navigation row: soft fill when selected, icon bounces on selection.
private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    var screen: AppModel.Screen
    @State private var hovering = false

    private var isSelected: Bool { model.screen == screen }

    var body: some View {
        Button {
            model.screen = screen
        } label: {
            HStack(spacing: Theme.s3) {
                Image(systemName: screen.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 20)
                    .symbolEffect(.bounce, value: isSelected)
                Text(screen.sidebarTitle)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.s3 - 2)
            .frame(height: Theme.sidebarRow)
            .background(isSelected ? Theme.selection : hovering ? Theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.r3, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("sidebar.\(screen.id)")
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
        var opens: AppModel.Screen
        var settingsSection: SettingsView.Section?
    }

    private var steps: [Step] {
        [
            Step(title: "Allow microphone", isDone: microphoneGranted, opens: .dictation),
            Step(title: "Allow speech recognition", isDone: speechGranted, opens: .dictation),
            Step(title: "Turn on text insertion", isDone: model.insertion.isEnabled, opens: .settings, settingsSection: .insertion),
            Step(title: "Finish a first dictation", isDone: !model.dictationHistory.isEmpty, opens: .dictation),
        ]
    }

    var body: some View {
        let completed = steps.filter(\.isDone).count
        Group {
            if completed < steps.count {
                VStack(alignment: .leading, spacing: Theme.s2) {
                    HStack {
                        Text("Get set up").font(.system(size: 13.5, weight: .semibold))
                        Spacer()
                        Text("\(completed) of \(steps.count)")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.ink3)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.hairline)
                            Capsule().fill(Theme.ink)
                                .frame(width: geo.size.width * CGFloat(completed) / CGFloat(steps.count))
                        }
                    }
                    .frame(height: 3)
                    .animation(Theme.gentle, value: completed)
                    ForEach(steps) { step in
                        Button {
                            if let section = step.settingsSection {
                                UserDefaults.standard.set(section.rawValue, forKey: "settingsSection")
                            }
                            model.screen = step.opens
                        } label: {
                            HStack(spacing: Theme.s2) {
                                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(step.isDone ? Theme.ink : Theme.ink3)
                                    .contentTransition(.symbolEffect(.replace))
                                Text(step.title)
                                    .font(.system(size: 13))
                                    .foregroundStyle(step.isDone ? Theme.ink3 : Theme.ink)
                                    .strikethrough(step.isDone, color: Theme.ink3)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(step.isDone)
                    }
                }
                .padding(Theme.s3)
                .background(Theme.sheet, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(Theme.gentle, value: completed)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: model.audio.isRunning) { _, _ in refresh() }
    }

    private func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }
}
