import SwiftUI

/// Download, progress and remove buttons for the optional local cleanup model, shown where
/// Polished needs it (Style, and Settings › Cleanup) on Macs without Apple Intelligence.
struct LocalCleanupModelControls: View {
    var isLocked = false
    private var localModel = LocalCleanupModel.shared

    init(isLocked: Bool = false) {
        self.isLocked = isLocked
    }

    var body: some View {
        switch localModel.phase {
        case .downloading:
            HStack(spacing: Theme.s3) {
                ProgressView(value: localModel.downloadFraction)
                    .tint(Theme.signal)
                    .accessibilityLabel("Downloading the cleanup model")
                Button("Cancel") { localModel.cancelDownload() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        case .loading:
            HStack(spacing: Theme.s3) {
                ProgressView().controlSize(.small).accessibilityLabel("Loading the cleanup model")
                Text("Loading…").font(.hkCaption).foregroundStyle(Theme.ink2)
            }
        default:
            HStack(spacing: Theme.s2) {
                if localModel.isDownloaded {
                    Button("Remove model") { localModel.removeModel() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(localModel.isBusy || isLocked)
                } else {
                    Button(downloadTitle) { localModel.download() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var downloadTitle: String {
        if case .failed = localModel.phase { return "Try again" }
        return "Download \(ByteCountFormatter.string(fromByteCount: localModel.file.bytes, countStyle: .file))"
    }
}
