import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let motion = model.motion
        let span = motion.latest.map { ($0.t - 8)...$0.t }

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Connect",
                           subtitle: "Teach HushKey words you mouth with AirPods in. Step one: live motion.")
                LabProgress()

                LabHero(symbol: statusSymbol, tint: statusColor, title: statusTitle, message: statusMessage) {
                    primaryActionButton
                } metrics: {
                    if motion.status == .streaming {
                        VStack(alignment: .trailing, spacing: Theme.s3) {
                            HeroMetric(value: String(format: "%.0f", motion.sampleRate), label: "samples per second")
                            HeroMetric(value: motion.sampleCount.formatted(), label: "samples received")
                        }
                    }
                }
                .animation(Theme.gentle, value: motion.status == .streaming)

                SettingsGroup(title: "Live motion",
                              footer: "Headphone motion is head and jaw movement, not a microphone or lip reading.") {
                    GroupRow {
                        SignalPlot(title: "User acceleration (g)", samples: motion.history,
                                   channels: SignalPlot.acceleration, span: span, minScale: 0.01)
                    }
                    GroupRow {
                        SignalPlot(title: "Rotation rate (rad/s)", samples: motion.history,
                                   channels: SignalPlot.rotation, span: span, minScale: 0.05)
                    }
                    GroupRow {
                        SignalPlot(title: "Attitude (rad)", samples: motion.history,
                                   channels: SignalPlot.attitude, span: span, minScale: 0.1)
                    }
                }

                ResearchRecordingSection()
            }
            .pageLayout()
        }
    }

    private var statusTitle: String {
        switch model.motion.status {
        case .unsupported: "Motion isn’t available"
        case .denied: "Motion access is off"
        case .waiting: "Waiting for headphones"
        case .streaming: "Motion is live"
        case .error: "Motion could not start"
        }
    }

    private var statusSymbol: String {
        switch model.motion.status {
        case .unsupported: "headphones.slash"
        case .denied: "hand.raised.slash"
        case .waiting: "headphones"
        case .streaming: "waveform.path"
        case .error: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch model.motion.status {
        case .streaming: Theme.signal
        case .waiting: Theme.ink2
        case .denied: Theme.finishing
        case .unsupported, .error: Theme.danger
        }
    }

    private var statusMessage: String {
        switch model.motion.status {
        case .streaming:
            "Your headphones are streaming. Next, record a few words."
        case .waiting:
            "Put in AirPods Pro or Max and pick them as the Mac’s sound output."
        case .denied:
            "Allow HushKey in Privacy & Security → Motion, then reopen it."
        case .unsupported:
            "These headphones don’t share head motion with the Mac."
        case .error(let message):
            "Motion could not start: \(message)"
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch model.motion.status {
        case .streaming:
            Button("Continue to Train", icon: .arrowRight) {
                model.screen = .train
            }
                .buttonStyle(PrimaryButtonStyle())
        case .denied:
            Button("Open Motion Settings", icon: .lock) {
                openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Motion")
            }
                .buttonStyle(SecondaryButtonStyle())
        case .waiting:
            Button("Bluetooth Settings", icon: .waveform) {
                openSystemSettings("x-apple.systempreferences:com.apple.BluetoothSettings")
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Sound Settings", icon: .speaker) {
                openSystemSettings("x-apple.systempreferences:com.apple.Sound-Settings.extension")
            }
            .buttonStyle(SecondaryButtonStyle())
        case .unsupported, .error:
            Button("Open Sound Settings", icon: .speaker) {
                openSystemSettings("x-apple.systempreferences:com.apple.Sound-Settings.extension")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func openSystemSettings(_ address: String) {
        guard let url = URL(string: address) else { return }
        openURL(url)
    }

}
