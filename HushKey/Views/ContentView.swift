import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List(selection: screenSelection) {
                Section("WRITE") {
                    Label(AppModel.Screen.dictation.rawValue, systemImage: AppModel.Screen.dictation.symbol)
                        .tag(AppModel.Screen.dictation)
                    Label(AppModel.Screen.transforms.rawValue, systemImage: AppModel.Screen.transforms.symbol)
                        .tag(AppModel.Screen.transforms)
                    Label(AppModel.Screen.files.rawValue, systemImage: AppModel.Screen.files.symbol)
                        .tag(AppModel.Screen.files)
                    Label(AppModel.Screen.meetings.rawValue, systemImage: AppModel.Screen.meetings.symbol)
                        .tag(AppModel.Screen.meetings)
                }
                Section("SILENT LAB") {
                    ForEach([AppModel.Screen.setup, .train, .evaluate, .use]) { screen in
                        Label(screen.rawValue, systemImage: screen.symbol).tag(screen)
                    }
                }
                Section("MANAGE") {
                    Label(AppModel.Screen.personalization.rawValue, systemImage: AppModel.Screen.personalization.symbol)
                        .tag(AppModel.Screen.personalization)
                    Label(AppModel.Screen.settings.rawValue, systemImage: AppModel.Screen.settings.symbol)
                        .tag(AppModel.Screen.settings)
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

    private var screenSelection: Binding<AppModel.Screen?> {
        Binding(get: { model.screen }, set: { if let screen = $0 { model.screen = screen } })
    }
}
