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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.s4, alignment: .top), count: 3)

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
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Style & Cleanup",
                           subtitle: "Choose how dictation is refined and tone is shaped. Everything runs on this Mac.")

                VStack(alignment: .leading, spacing: Theme.s3) {
                    Text("Cleanup level").font(.hkTitle3)
                    Text("Controls how much speech polishing happens after you release the key.")
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)

                    LazyVGrid(columns: columns, spacing: Theme.s4) {
                        ForEach(CleanupLevel.allCases) { level in
                            CleanupLevelCard(
                                level: level,
                                isSelected: currentCleanupLevel == level,
                                hasAI: DictationSmartCleanup.isAvailable,
                                onSelect: { setCleanupLevel(level) }
                            )
                            // Polished needs Apple Intelligence or the local model; without either it can't be chosen.
                            .disabled(level == .polished && !DictationSmartCleanup.isAvailable)
                            .opacity(level == .polished && !DictationSmartCleanup.isAvailable ? 0.5 : 1)
                            .help(level == .polished && !DictationSmartCleanup.isAvailable
                                  ? "Download the on-device cleanup model below, or turn on Apple Intelligence" : "")
                        }
                    }

                    if !DictationSmartCleanup.hasAppleIntelligence {
                        localModelRow
                    }

                    Label("HushKey never rewords or invents text. The polish pass only deletes fillers and refines punctuation. The raw transcript is always one click away in History.", icon: .shield)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                }

                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, Theme.s2)

                VStack(alignment: .leading, spacing: Theme.s3) {
                    Text("Tone per context").font(.hkTitle3)
                    UnderlineTabs(selection: $context, options: DictationContext.allCases.map { ($0, $0.rawValue) })
                    appsRow
                    LazyVGrid(columns: columns, spacing: Theme.s4) {
                        ForEach(DictationTone.allCases) { tone in
                            ToneCard(tone: tone, sample: context.sample,
                                     isSelected: model.dictationToneSettings.tone(for: context) == tone) {
                                withAnimation(Theme.snappy) { model.dictationToneSettings.tones[context] = tone }
                            }
                        }
                    }
                    Label("Code mode is never restyled, and snippets keep the text you wrote.", icon: .info)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                }
            }
            .pageLayout()
        }
    }

    /// Without Apple Intelligence, Polished runs on a small model you download here.
    private var localModelRow: some View {
        HStack(alignment: .center, spacing: Theme.s4) {
            Glyph(.sparkle, size: 17)
                .foregroundStyle(Theme.signal)
            Text(LocalCleanupModel.shared.statusDescription)
                .font(.hkCallout)
                .foregroundStyle(isLocalModelFailed ? Theme.danger : Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            LocalCleanupModelControls(isLocked: model.audio.isRunning || model.isFinalizingDictation)
        }
        .padding(Theme.s4)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var isLocalModelFailed: Bool {
        if case .failed = LocalCleanupModel.shared.phase { return true }
        return false
    }

    private var appsRow: some View {
        HStack(spacing: Theme.s2) {
            SymbolGlyph(context.symbol, size: 17)
                .foregroundStyle(Theme.signal)
            Text("Applies in")
                .font(.hkCallout)
                .foregroundStyle(Theme.ink2)
            ForEach(context.exampleApps, id: \.self) { app in
                Text(app)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, Theme.s2)
                    .padding(.vertical, Theme.s1)
                    .background(Capsule().fill(Theme.well))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CleanupLevelCard: View {
    var level: CleanupLevel
    var isSelected: Bool
    var hasAI: Bool
    var onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.s3) {
                HStack {
                    Text(level.rawValue).font(.hkHeadline).foregroundStyle(Theme.ink)
                    Spacer()
                    Glyph(isSelected ? .checkCircle : .record)
                        .foregroundStyle(isSelected ? Theme.signal : Theme.ink3)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(level.detail).font(.hkCaption).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Example:")
                        .font(.hkMeta.weight(.semibold))
                        .foregroundStyle(Theme.ink3)
                    Text(level.sampleAfter(hasAI: hasAI))
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.s3)
                .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous).fill(Theme.sheet))
            }
            .padding(Theme.s4)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .fill(isSelected ? Theme.signalSoft : hovering ? Theme.hover : Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(isSelected ? Theme.signal : Theme.hairline, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
        .accessibilityLabel("\(level.rawValue). \(level.detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ToneCard: View {
    var tone: DictationTone
    var sample: String
    var isSelected: Bool
    var select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: Theme.s3) {
                HStack {
                    Text(tone.rawValue).font(.hkHeadline).foregroundStyle(Theme.ink)
                    Spacer()
                    Glyph(isSelected ? .checkCircle : .record)
                        .foregroundStyle(isSelected ? Theme.signal : Theme.ink3)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(tone.detail).font(.hkCaption).foregroundStyle(Theme.ink2)
                Text(tone.apply(to: sample))
                    .font(.hkCallout)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Theme.s3)
                    .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous).fill(Theme.sheet))
                    .contentTransition(.opacity)
            }
            .padding(Theme.s4)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .fill(isSelected ? Theme.signalSoft : hovering ? Theme.hover : Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous)
                .strokeBorder(isSelected ? Theme.signal : Theme.hairline, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
        .accessibilityLabel("\(tone.rawValue). \(tone.detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
