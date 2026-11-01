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
            Button("Open HushKey") { openWindow(id: "main") }
            Divider()
            Label(model.motion.status.label, systemImage: model.motion.isConnected ? "headphones" : "headphones.slash")
            Text("Local silent-mouthing experiment")
                .font(.caption)
        }
        .menuBarExtraStyle(.menu)
    }
}
