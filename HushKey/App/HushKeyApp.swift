import SwiftUI

@main
struct HushKeyApp: App {
    @State private var model = AppModel()
    @State private var pill = FloatingPillController()
    @State private var silentHUD = SilentCaptureHUDController()
    @Environment(\.openWindow) private var openWindow

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
                .environment(model)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    model.openMainWindow = { openWindow(id: "main") }
                    model.start()
                    pill.attach(to: model)
                    silentHUD.attach(to: model)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
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
            Button("Open HushKey") {
                model.screen = .dictation
                openWindow(id: "main")
            }
            Toggle("Show dictation pill", isOn: Binding(
                get: { model.showsFloatingPill },
                set: { model.showsFloatingPill = $0 }))
            Toggle("Dictation sounds", isOn: Binding(
                get: { model.playsDictationSounds },
                set: { model.playsDictationSounds = $0 }))
            Divider()
            Label(model.motion.status.label, systemImage: model.motion.isConnected ? "headphones" : "headphones.slash")
            Text(model.meetingNotes.isCapturing ? "Meeting capture is active · Audio stays on this Mac" : "Local dictation · Silent lab")
                .font(.caption)
        } label: {
            // The keycap glyph; its ribbon opens into a lens while dictating.
            Image(model.audio.isRunning ? "HushKeyMenuBarLive" : "HushKeyMenuBar")
                .accessibilityLabel("HushKey")
        }
        .menuBarExtraStyle(.menu)
    }
}
