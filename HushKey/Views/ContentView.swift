import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List(selection: screenSelection) {
                Section("WRITE") {
                    sidebarItem(.dictation)
                    sidebarItem(.transforms)
                    sidebarItem(.files)
                    sidebarItem(.meetings)
                }
                Section("SILENT LAB") {
                    ForEach([AppModel.Screen.setup, .train, .evaluate, .use]) { screen in
                        sidebarItem(screen)
                    }
                }
                Section("MANAGE") {
                    sidebarItem(.personalization)
                    sidebarItem(.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
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

    private func sidebarItem(_ screen: AppModel.Screen) -> some View {
        Label(screen.rawValue, systemImage: screen.symbol)
            .tag(screen)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(screen.rawValue)
            .accessibilityIdentifier("sidebar.\(screen.id)")
    }

    private var screenSelection: Binding<AppModel.Screen?> {
        Binding(get: { model.screen }, set: { if let screen = $0 { model.screen = screen } })
    }
}
