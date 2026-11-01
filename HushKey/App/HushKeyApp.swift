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
        .windowResizability(.contentMinSize)

        MenuBarExtra("HushKey", image: "HushKeyMenuBar") {
            Button(model.audio.isRunning ? "Stop dictation" : "Start dictation") {
                Task { await model.toggleDictation() }
            }
            Button("Open HushKey") {
                model.screen = .dictation
                openWindow(id: "main")
            }
            Toggle("Show dictation pill", isOn: Binding(
                get: { model.showsFloatingPill },
                set: { model.showsFloatingPill = $0 }))
            Divider()
            Label(model.motion.status.label, systemImage: model.motion.isConnected ? "headphones" : "headphones.slash")
            Text("Local dictation · Silent lab")
                .font(.caption)
        }
        .menuBarExtraStyle(.menu)
    }
}
