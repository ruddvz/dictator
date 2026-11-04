import SwiftUI

/// Tone per kind of app: formal, casual or very casual, previewed on a sample message with
/// the same on-device formatter dictation uses.
struct StyleView: View {
    @Environment(AppModel.self) private var model
    @State private var context: DictationContext = .personal

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.s4, alignment: .top), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Style",
                           subtitle: "Choose how dictation reads in each kind of app. Formatting happens on this Mac.")
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
            .pageLayout()
        }
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
