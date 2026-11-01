import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List(selection: screenSelection) {
                Section("STUDY") {
                    ForEach([AppModel.Screen.setup, .train, .evaluate, .use]) { screen in
                        Label(screen.rawValue, systemImage: screen.symbol).tag(screen)
                    }
                }
                Section("MANAGE") {
                    Label(AppModel.Screen.settings.rawValue, systemImage: AppModel.Screen.settings.symbol)
                        .tag(AppModel.Screen.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch model.screen {
            case .setup: SetupView()
            case .train: TrainView()
            case .evaluate: EvaluateView()
            case .use: UseView()
            case .settings: SettingsView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                MotionStatusBadge(status: model.motion.status, rate: model.motion.sampleRate)
            }
        }
        .navigationTitle(model.screen.rawValue)
    }

    private var screenSelection: Binding<AppModel.Screen?> {
        Binding(get: { model.screen }, set: { if let screen = $0 { model.screen = screen } })
    }
}
