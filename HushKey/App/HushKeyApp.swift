import CoreAudio
import SwiftUI

@main
struct HushKeyApp: App {
    @NSApplicationDelegateAdaptor(HushKeyAppDelegate.self) private var appDelegate

    init() {
        Self.handOffToRunningCopy()
    }

    /// Only one HushKey may run: two would both watch fn and Control, both own the pill, and fight
    /// over the microphone. A second launch (another build, a copy elsewhere on disk) brings the
    /// running one forward and quits.
    private static func handOffToRunningCopy() {
        guard !AppDataDirectory.isRunningTests, let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != current.processIdentifier && !$0.isTerminated }) else { return }
        running.activate()
        exit(0)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appDelegate.model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .help) {
                Button("HushKey Setup Tour…") { appDelegate.model.openOnboarding() }
            }
        }

        MenuBarExtra {
            HushKeyMenu(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Owns the model so dictation, the fn key, the pill and the menu bar work from launch, whether
/// or not the HushKey window is ever opened, like Wispr Flow or TypeWhisper. Closing the window
/// leaves HushKey running in the menu bar.
@MainActor
final class HushKeyAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let pill = FloatingPillController()
    private let silentHUD = SilentCaptureHUDController()
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = Self.isLoginItemLaunch()
        // A normal launch opens the hub, so start in the Dock; a login launch stays in the menu bar.
        model.isHubWindowOpen = !launchedAtLogin
        model.applyDockVisibility()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppDataDirectory.isRunningTests else { return }
        model.start()
        observeHubWindows()
        pill.attach(to: model)
        silentHUD.attach(to: model)
        model.enableLaunchAtLoginOnFirstRun()
        // Started by the login item: stay in the menu bar, as the window SwiftUI opened isn't wanted.
        if launchedAtLogin {
            DispatchQueue.main.async {
                for window in NSApp.windows where window.isVisible && window.canBecomeMain { window.close() }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Tracks whether the hub window is open, so the Dock icon can follow it (menu bar first).
    private func observeHubWindows() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didDeminiaturizeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                guard window.sheetParent == nil else { return }
                guard window.canBecomeMain else { return }
                MainActor.assumeIsolated { self?.model.isHubWindowOpen = true }
            }
        }
        // After a close or minimise, look again once AppKit has updated its window list.
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let closing = note.object as? NSWindow else { return }
                guard closing.sheetParent == nil else { return }
                guard closing.canBecomeMain else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.model.isHubWindowOpen = NSApp.windows.contains {
                            $0 !== closing && $0.sheetParent == nil && $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain
                        }
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForTermination()
        // ggml's Metal backend aborts at exit if a model is still loaded.
        LocalCleanupModel.unloadAllBeforeExit()
    }

    private static func isLoginItemLaunch() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}

/// The menu bar glyph. It also gives the model a way to open the window that doesn't depend on the
/// window having been opened once, since the label is drawn at launch.
private struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 3) {
            Image(model.audio.isRunning ? "HushKeyMenuBarLive" : "HushKeyMenuBar")
            if model.audio.isRunning {
                Circle()
                    .fill(Theme.signal)
                    .frame(width: 5, height: 5)
            } else if model.isFinalizingDictation || model.transcriber.isFinalizing {
                Circle()
                    .fill(Theme.finishing)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("HushKey")
        .task {
            model.openMainWindow = {
                model.isHubWindowOpen = true
                // Bring the hub back if it is already open: openWindow on a WindowGroup always
                // makes another window, so Open from the pill used to stack a second hub.
                if let hub = NSApp.windows.first(where: { window in
                    !(window is NSPanel) && window.canBecomeMain && (window.isVisible || window.isMiniaturized)
                }) {
                    if hub.isMiniaturized { hub.deminiaturize(nil) }
                    hub.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

private struct HushKeyMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        let isTranscribing = model.isFinalizingDictation || model.transcriber.isFinalizing
        let meetingBusy = model.meetingNotes.isStarting || model.meetingNotes.isFinalizing
        let lastText = model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Status line first
        Text(statusLine)
            .font(.caption)

        Divider()

        // 2. Start / Stop
        Button(model.meetingNotes.isCapturing ? "Stop Meeting and Save" :
               meetingBusy ? "Starting Meeting…" :
               model.isFinalizingSelectedTextEdit ? "Finishing Voice Edit…" :
               model.isSelectedTextEditCapturing ? "Stop Voice Edit" :
               model.isStartingSelectedTextEdit ? "Cancel Voice Edit" :
               isTranscribing ? "Finishing Dictation…" :
               model.audio.isRunning ? "Stop Dictation" : "Start Dictation") {
            if model.meetingNotes.isCapturing {
                model.meetingNotes.stop()
            } else {
                Task { await model.toggleDictation() }
            }
        }
        .disabled(meetingBusy || isTranscribing)
        if !model.meetingNotes.isCapturing {
            Button("Record Meeting") { model.startMeeting() }
                .disabled(meetingBusy || isTranscribing || model.audio.isRunning)
        }

        Divider()

        // 3. Submenus: Microphone, Language, Engine
        Menu("Microphone") {
            Picker("Microphone", selection: Binding(get: { model.audio.selectedDeviceID },
                                                    set: { model.audio.selectedDeviceID = $0 })) {
                Text("System default").tag(AudioDeviceID?.none)
                ForEach(model.audio.devices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .pickerStyle(.inline)
        }
        .disabled(model.audio.isRunning || model.audio.isStarting)

        Menu("Language") {
            Picker("Language", selection: $model.dictationLanguage) {
                // The same on-device list as Settings, so any saved language shows as selected.
                ForEach(DictationLanguage.onDevice) { language in
                    Text(language.name).tag(language.identifier)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("More Languages…") {
                model.screen = .settings
                UserDefaults.standard.set(SettingsView.Section.dictation.rawValue, forKey: "settingsSection")
                model.openMainWindow?()
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Menu("Engine") {
            Picker("Engine", selection: $model.dictationEngine) {
                Text("Apple Speech").tag(DictationEngine.appleSpeech)
                if model.parakeet.isDownloaded {
                    Text("Parakeet (more accurate)").tag(DictationEngine.parakeet)
                }
            }
            .pickerStyle(.inline)
            if !model.parakeet.isDownloaded {
                Divider()
                Button("Download Parakeet…") {
                    model.screen = .settings
                    UserDefaults.standard.set(SettingsView.Section.dictation.rawValue, forKey: "settingsSection")
                    model.openMainWindow?()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }

        Divider()

        // 4. History, Transcribe file, Recovery, Last transcription
        Button("Show History") {
            model.screen = .dictation
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Transcribe a File…") {
            model.screen = .files
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }

        if model.canRecoverLastRecording {
            Button("Recover Last Recording") {
                Task { await model.recoverLastRecording() }
            }
        }

        Menu("Last Dictation") {
            Button("Copy") {
                model.copyDictationText()
            }
            .disabled(lastText.isEmpty)

            Button("Paste Again") {
                Task { await model.pasteLastDictationAgain() }
            }
            .disabled(lastText.isEmpty)
        }

        Divider()

        // 5. Global controls
        Toggle("Pause Shortcuts", isOn: $model.isShortcutsPaused)
        if model.pillHiddenUntil != nil {
            Button("Show Dictation Bar Now") { model.unhideFloatingPill() }
        } else {
            Toggle("Show Dictation Bar", isOn: $model.showsFloatingPill)
        }
        Toggle("Dictation Sounds", isOn: $model.playsDictationSounds)
        Toggle("Mute Audio While Dictating", isOn: $model.mutesAudioWhileDictating)

        Divider()

        // 6. Hub navigation & Quit
        Button("Open HushKey") {
            model.screen = .dictation
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings…") {
            model.screen = .settings
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit HushKey") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if model.audio.isRunning {
            return model.meetingNotes.isCapturing ? "Recording a meeting" : "Listening…"
        }
        if model.isFinalizingDictation || model.transcriber.isFinalizing {
            return "Transcribing…"
        }
        if model.isStartingDictation || model.audio.isStarting {
            return "Opening microphone…"
        }
        if model.isShortcutsPaused {
            return "Shortcuts paused"
        }
        if model.dictationShortcutNeedsAttention {
            return model.dictationShortcutStatus
        }
        return "HushKey · Ready"
    }
}
