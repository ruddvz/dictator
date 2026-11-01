import SwiftUI

@main
struct HushKeyApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 680)
                .task { model.start() }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("HushKey", image: "HushKeyMenuBar") {
            let meetingBusy = model.meetingNotes.isStarting || model.meetingNotes.isFinalizing
            Button(model.meetingNotes.isCapturing ? "Stop meeting capture" :
                   meetingBusy ? "Meeting capture…" :
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
            Divider()
            Label(model.motion.status.label, systemImage: model.motion.isConnected ? "headphones" : "headphones.slash")
            Text(model.meetingNotes.isCapturing ? "Meeting capture is active · Audio stays on this Mac" : "Local dictation · Silent lab")
                .font(.caption)
        }
        .menuBarExtraStyle(.menu)
    }
}
