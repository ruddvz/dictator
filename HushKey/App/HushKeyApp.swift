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
        model.applyDockVisibility()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppDataDirectory.isRunningTests else { return }
        model.start()
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

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForTermination()
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
        // The breath ribbon; it opens into a fuller lens while dictating.
        Image(model.audio.isRunning ? "HushKeyMenuBarLive" : "HushKeyMenuBar")
            .accessibilityLabel("HushKey")
            .task {
                model.openMainWindow = {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

private struct HushKeyMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        let meetingBusy = model.meetingNotes.isStarting || model.meetingNotes.isFinalizing
        Button(model.meetingNotes.isCapturing ? "Stop meeting capture" :
               meetingBusy ? "Meeting capture…" :
               model.isFinalizingSelectedTextEdit ? "Finishing voice edit…" :
               model.isSelectedTextEditCapturing ? "Stop voice edit" :
               model.isStartingSelectedTextEdit ? "Cancel voice edit start" :
               model.audio.isRunning ? "Stop dictation" : "Start dictation") {
            if model.meetingNotes.isCapturing {
                model.meetingNotes.stop()
            } else {
                Task { await model.toggleDictation() }
            }
        }
        .disabled(meetingBusy)
        Button("Paste last transcript") {
            Task { await model.pasteLastDictationAgain() }
        }
        .disabled(model.transcriber.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Divider()
        Button("Open HushKey") {
            model.screen = .dictation
            model.openMainWindow?()
        }
        Button("Settings…") {
            model.screen = .settings
            model.openMainWindow?()
        }
        .keyboardShortcut(",")
        Divider()
        Picker("Microphone", selection: Binding(get: { model.audio.selectedDeviceID },
                                                set: { model.audio.selectedDeviceID = $0 })) {
            Text("System default").tag(AudioDeviceID?.none)
            ForEach(model.audio.devices) { device in
                Text(device.name).tag(Optional(device.id))
            }
        }
        .disabled(model.audio.isRunning || model.audio.isStarting)
        Toggle("Show dictation bar", isOn: $model.showsFloatingPill)
        Toggle("Dictation sounds", isOn: $model.playsDictationSounds)
        Toggle("Mute audio while dictating", isOn: $model.mutesAudioWhileDictating)
        Divider()
        Label(model.motion.status.label, systemImage: model.motion.isConnected ? "headphones" : "headphones.slash")
        Text(model.meetingNotes.isCapturing ? "Meeting capture is active · Audio stays on this Mac" : "Local dictation · Silent lab")
            .font(.caption)
        Divider()
        Button("Quit HushKey") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
