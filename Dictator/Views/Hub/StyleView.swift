import SwiftUI

enum CleanupLevel: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case clean = "Clean"
    case polished = "Polished"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .raw: "Verbatim speech. Every hesitation, repeated word and false start is kept."
        case .clean: "Removes um, uh, stutters and “no actually” backtracks using local text rules."
        case .polished: "Cleaned plus an on-device model that drops the fillers rules miss and fixes punctuation."
        }
    }

    var sampleBefore: String {
        "Um, we could, like, meet at four PM, no actually 5 PM."
    }

    func sampleAfter(hasAI: Bool) -> String {
        switch self {
        case .raw:
            return "Um, we could, like, meet at four PM, no actually 5 PM."
        case .clean:
            return "We could meet at 5 PM."
        case .polished:
            return hasAI ? "We could meet at 5:00 PM." : "We could meet at 5 PM."
        }
    }
}

/// Tone and cleanup levels: raw, clean or polished, previewed on real sentences with
/// the same on-device formatter dictation uses.
struct StyleView: View {
    @Environment(AppModel.self) private var model
    @State private var context: DictationContext = .personal

    private var currentCleanupLevel: CleanupLevel {
        if !model.cleansDictationFillers && !model.appliesSpokenCorrections { return .raw }
        if model.polishesWithAppleIntelligence && DictationSmartCleanup.isAvailable { return .polished }
        return .clean
    }

    private func setCleanupLevel(_ level: CleanupLevel) {
        withAnimation(Theme.snappy) {
            switch level {
            case .raw:
                model.appliesSpokenCorrections = false
                model.cleansDictationFillers = false
                model.polishesWithAppleIntelligence = false
            case .clean:
                model.appliesSpokenCorrections = true
                model.cleansDictationFillers = true
                model.polishesWithAppleIntelligence = false
            case .polished:
                model.appliesSpokenCorrections = true
                model.cleansDictationFillers = true
                model.polishesWithAppleIntelligence = true
            }
        }
    }

    var body: some View {
        ScrollView {
            PageColumn {
                PageHeader(title: "Style",
                           subtitle: "Choose how dictation is refined and tone is shaped. Everything runs on this Mac.")

                PageSection("Cleanup level",
                            subtitle: "Controls how much speech polishing happens after you release the key.") {
                    CardGrid(items: CleanupLevel.allCases) { level in
                        let unavailable = level == .polished && !DictationSmartCleanup.isAvailable
                        SelectableCard(title: level.rawValue, detail: level.detail,
                                       isSelected: currentCleanupLevel == level,
                                       action: { setCleanupLevel(level) }) {
                            VoiceSample(text: level.sampleAfter(hasAI: DictationSmartCleanup.isAvailable),
                                        isSelected: currentCleanupLevel == level)
                        }
                        // Polished needs Apple Intelligence or the local model; without either it can't be chosen.
                        .disabled(unavailable)
                        .opacity(unavailable ? Theme.disabledOpacity : 1)
                        .help(unavailable ? "Download the on-device cleanup model below, or turn on Apple Intelligence" : "")
                    }

                    if !DictationSmartCleanup.hasAppleIntelligence {
                        localModelRow
                    }

                    Text("Polish removes fillers and refines punctuation. Your raw transcript stays in History.")
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionRule()

                PageSection("Tone per context") {
                    UnderlineTabs(selection: $context, options: DictationContext.allCases.map { ($0, $0.rawValue) })
                    appsRow
                    CardGrid(items: DictationTone.allCases) { tone in
                        let selected = model.dictationToneSettings.tone(for: context) == tone
                        SelectableCard(title: tone.rawValue, detail: tone.detail, isSelected: selected,
                                       action: {
                                           withAnimation(Theme.snappy) { model.dictationToneSettings.tones[context] = tone }
                                       }) {
                            VoiceSample(text: tone.apply(to: context.sample), isSelected: selected)
                                .contentTransition(.opacity)
                        }
                    }
                    Text("Code mode is never restyled, and snippets keep the text you wrote.")
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                }
            }
        }
    }

    /// Without Apple Intelligence, Polished runs on a small model you download here.
    private var localModelRow: some View {
        HStack(alignment: .center, spacing: Theme.s4) {
            Glyph(.sparkle, size: Theme.iconL)
                .foregroundStyle(Theme.ink2)
            Text(LocalCleanupModel.shared.statusDescription)
                .font(.hkCallout)
                .foregroundStyle(isLocalModelFailed ? Theme.danger : Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            LocalCleanupModelControls(isLocked: model.audio.isRunning || model.isFinalizingDictation)
        }
        .card()
    }

    private var isLocalModelFailed: Bool {
        if case .failed = LocalCleanupModel.shared.phase { return true }
        return false
    }

    /// "Applies in Messages, WhatsApp and Signal." as one plain sentence.
    private var appsRow: some View {
        Text("Applies in \(context.exampleApps.formatted(.list(type: .and))).")
            .font(.hkCallout)
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A short quoted sample set in the serif face, hung off a thin leading rule that turns sage when chosen.
private struct VoiceSample: View {
    var text: String
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.s3) {
            Capsule()
                .fill(isSelected ? Theme.signal : Theme.hairline)
                .frame(width: Theme.ruleWidth)
            Text("“\(text)”")
                .font(.hkQuote)
                .foregroundStyle(Theme.ink)
                .lineSpacing(Theme.s0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
