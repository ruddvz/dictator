import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let motion = model.motion
        let span = motion.latest.map { ($0.t - 8)...$0.t }

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "Step 1 · Prepare",
                    title: "Check your motion signal",
                    subtitle: "HushKey reads processed head motion from compatible headphones. Confirm a live stream before collecting examples.")

                HStack(alignment: .top, spacing: 16) {
                    readinessCard
                    nextStepsCard
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
                    .padding(.top, 12)
                } label: {
                    Label("Motion diagnostics", systemImage: "waveform.path.ecg")
                        .font(.headline)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))

                Label("This is a small-vocabulary experiment. Head motion is not an inward microphone or a hidden speech sensor.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var readinessCard: some View {
        let motion = model.motion
        let ready = motion.status == .streaming

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Headphone motion", systemImage: "airpodspro")
                    .font(.headline)
                Spacer()
                StatusPill(title: ready ? "LIVE" : statusTitle,
                           symbol: ready ? "waveform" : "exclamationmark.circle",
                           tint: ready ? .green : .orange)
            }

            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 28) {
                metric("Sample rate", ready ? String(format: "%.1f Hz", motion.sampleRate) : "—")
                metric("Samples received", "\(motion.sampleCount)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ready ? Color.green.opacity(0.35) : Color.orange.opacity(0.28)))
    }

    private var nextStepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Study path")
                .font(.headline)
            StudyStep(number: "1", title: "Check motion", detail: "Connect headphones as the Mac’s audio output.", state: model.motion.status == .streaming ? .done : .current)
            StudyStep(number: "2", title: "Train words", detail: "Collect 10 examples each for at least 5 words.", state: model.motion.status == .streaming ? .current : .next)
            StudyStep(number: "3", title: "Evaluate", detail: "Compare against chance and a separate session.", state: .next)
            StudyStep(number: "4", title: "Try Use", detail: "Only unlock silent decoding if the evidence passes.", state: .next)
            HStack {
                Spacer()
                Button("Continue to training", systemImage: "arrow.right") {
                    model.screen = .train
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.motion.status != .streaming)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
    }

    private var statusTitle: String {
        switch model.motion.status {
        case .unsupported: "UNAVAILABLE"
        case .denied: "PERMISSION"
        case .waiting: "WAITING"
        case .streaming: "LIVE"
        case .error: "ERROR"
        }
    }

    private var statusMessage: String {
        switch model.motion.status {
        case .streaming:
            "A live motion stream is arriving. HushKey can now record training examples."
        case .waiting:
            "Connect compatible head-tracking headphones and select them as this Mac’s active audio output. HushKey checks capability from the live stream; it cannot identify the exact AirPods model."
        case .denied:
            "Motion access is off. Allow HushKey under System Settings → Privacy & Security → Motion, then reopen the app."
        case .unsupported:
            "This Mac or the connected headphones do not provide the public headphone-motion API HushKey needs."
        case .error(let message):
            "Motion could not start: \(message)"
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
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
                .foregroundStyle(state == .done ? Color.green : state == .current ? Color.accentColor : Color.secondary)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number)  \(title)")
                    .font(.callout.weight(state == .current ? .semibold : .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
