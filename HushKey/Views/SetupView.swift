import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let motion = model.motion
        let span = motion.latest.map { ($0.t - 8)...$0.t }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: "Step 1 · Prepare",
                    title: "Connect your headphones",
                    subtitle: "Confirm HushKey is receiving live motion before you start the study.")

                HStack(alignment: .top, spacing: 14) {
                    connectionCard
                    studyPathCard
                }

                DisclosureGroup {
                    VStack(spacing: 12) {
                        SignalPlot(title: "User acceleration (g)", samples: motion.history,
                                   channels: SignalPlot.acceleration, span: span, minScale: 0.01)
                        SignalPlot(title: "Rotation rate (rad/s)", samples: motion.history,
                                   channels: SignalPlot.rotation, span: span, minScale: 0.05)
                        SignalPlot(title: "Attitude (rad)", samples: motion.history,
                                   channels: SignalPlot.attitude, span: span, minScale: 0.1)
                    }
                    .padding(.top, 10)
                } label: {
                    Label("Motion diagnostics", systemImage: "waveform.path.ecg")
                        .font(.headline)
                }

                Label("Headphone motion is not an inward-facing microphone or a lip-reading sensor.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .pageLayout()
        }
    }

    private var connectionCard: some View {
        let motion = model.motion
        let ready = motion.status == .streaming

        return GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: statusSymbol)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.headline)
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                HStack(spacing: 22) {
                    metric("Sample rate", ready ? String(format: "%.1f Hz", motion.sampleRate) : "—")
                    metric("Samples", "\(motion.sampleCount)")
                }

                HStack {
                    Spacer()
                    primaryActionButton
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var studyPathCard: some View {
        let trained = model.dataset.vocabulary.count >= 5 &&
            model.dataset.vocabulary.allSatisfy { model.templateCount(for: $0, condition: .silent) >= 10 }
        let connected = model.motion.status == .streaming
        let passed = model.isMotionInferenceEnabled
        return GroupBox("Study path") {
            VStack(alignment: .leading, spacing: 13) {
                StudyStep(number: "1", title: "Check motion", detail: connected ? "A live headphone-motion stream is arriving." : "Connect compatible headphones as the Mac’s sound output.", state: connected ? .done : .current)
                StudyStep(number: "2", title: "Train words", detail: trained ? "The silent set has 10 takes each for at least 5 words." : "Collect 10 takes each for at least 5 words.", state: trained ? .done : connected ? .current : .next)
                StudyStep(number: "3", title: "Evaluate", detail: passed ? "The held-out silent result passes the evidence checks." : "Run the significance and separate-session checks.", state: passed ? .done : trained ? .current : .next)
                StudyStep(number: "4", title: "Try Silent Use", detail: passed ? "Experimental silent decoding is available." : "Silent decoding unlocks only if every evidence check passes.", state: passed ? .done : .next)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        case .streaming: .green
        case .waiting: .secondary
        case .denied: .orange
        case .unsupported, .error: .red
        }
    }

    private var statusMessage: String {
        switch model.motion.status {
        case .streaming:
            "A live motion stream is arriving. You can now collect training examples."
        case .waiting:
            "No compatible headphone-motion stream is arriving. Pair your headphones in Bluetooth settings, then select them under Sound → Output. HushKey confirms support when live samples arrive."
        case .denied:
            "Allow HushKey under System Settings → Privacy & Security → Motion, then reopen the app."
        case .unsupported:
            "This Mac or the selected headphones do not provide the public headphone-motion API HushKey needs."
        case .error(let message):
            "Motion could not start: \(message)"
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch model.motion.status {
        case .streaming:
            Button("Continue to training", systemImage: "arrow.right") {
                model.screen = .train
            }
                .buttonStyle(.borderedProminent)
        case .denied:
            Button("Open Motion Settings", systemImage: "lock.open") {
                openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Motion")
            }
                .buttonStyle(.bordered)
        case .waiting:
            Button("Bluetooth Settings", systemImage: "dot.radiowaves.left.and.right") {
                openSystemSettings("x-apple.systempreferences:com.apple.BluetoothSettings")
            }
            .buttonStyle(.borderedProminent)
            Button("Sound Settings", systemImage: "speaker.wave.2") {
                openSystemSettings("x-apple.systempreferences:com.apple.Sound-Settings.extension")
            }
            .buttonStyle(.bordered)
        case .unsupported, .error:
            Button("Open Sound Settings", systemImage: "speaker.wave.2") {
                openSystemSettings("x-apple.systempreferences:com.apple.Sound-Settings.extension")
            }
            .buttonStyle(.bordered)
        }
    }

    private func openSystemSettings(_ address: String) {
        guard let url = URL(string: address) else { return }
        openURL(url)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}

private struct StudyStep: View {
    enum State: Equatable { case done, current, next }

    var number: String
    var title: String
    var detail: String
    var state: State

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state == .done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(state == .done ? Color.green : state == .current ? Theme.ink : Color.secondary)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number)  \(title)")
                    .font(.callout.weight(state == .current ? .semibold : .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
