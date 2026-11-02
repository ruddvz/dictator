import SwiftUI

@main
struct HushKeyApp: App {
    @State private var model = AppModel()
    @State private var pill = FloatingPillController()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    model.start()
                    pill.attach(to: model)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra("HushKey", image: "HushKeyMenuBar") {
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
            Divider()
            Label(model.motion.status.label, systemImage: model.motion.isConnected ? "headphones" : "headphones.slash")
            Text(model.meetingNotes.isCapturing ? "Meeting capture is active · Audio stays on this Mac" : "Local dictation · Silent lab")
                .font(.caption)
        }
        .menuBarExtraStyle(.menu)
    }
}
