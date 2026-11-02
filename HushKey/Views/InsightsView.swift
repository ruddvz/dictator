import SwiftUI

/// Lifetime numbers from the local usage ledger: pace, cleanup, words, where you dictate and
/// your streak. Counts only; everything stays on this Mac.
struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    private var ledger: UsageLedger { model.usageLedger }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Insights",
                           subtitle: "Counted on this Mac from finished dictations. Only daily totals are kept, never text.")
                if ledger.totalDictations == 0 {
                    Text(model.savesDictationHistory
                         ? "Finish a dictation and your numbers start here."
                         : "Insights are recorded only while saving history is on in Settings.")
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                }
                HStack(alignment: .top, spacing: Theme.s4) {
                    speedCard
                    cleanupCard
                    wordsCard
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: Theme.s4) {
                    categoriesCard
                    streakCard
                }
                .fixedSize(horizontal: false, vertical: true)
                Button("Reset insights…") { confirmReset = true }
                    .buttonStyle(.plain)
                    .font(.hkCaption)
                    .foregroundStyle(Theme.ink2)
                    .disabled(ledger.totalDictations == 0)
                    .confirmationDialog("Reset insights?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { model.resetUsageInsights() }
                    } message: {
                        Text("Clears these totals and your streak. History is not changed.")
                    }
            }
            .pageLayout(maxWidth: Theme.homeWidth)
        }
    }

    // MARK: Cards

    private var speedCard: some View {
        let wpm = ledger.wordsPerMinute ?? 0
        let ratio = Double(wpm) / Double(UsageLedger.typingWordsPerMinute)
        return InsightCard {
            Metric(value: wpm.formatted(), label: "Words per minute")
            ZStack {
                PaceArc(progress: min(1, Double(wpm) / 200))
                    .frame(width: 150, height: 80)
                VStack(spacing: 0) {
                    Text(wpm == 0 ? "–" : ratio.formatted(.number.precision(.fractionLength(1))) + "×")
                        .font(.display(22))
                    Text("typing speed").font(.hkCaption).foregroundStyle(Theme.ink2)
                }
                .offset(y: 16)
            }
            .frame(maxWidth: .infinity)
            .help("Compared with typing at about \(UsageLedger.typingWordsPerMinute) words per minute")
        }
    }

    private var cleanupCard: some View {
        InsightCard {
            Metric(value: ledger.wordsCleaned.formatted(), label: "Words cleaned up")
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text("\(ledger.totalDictations.formatted()) dictation\(ledger.totalDictations == 1 ? "" : "s")")
                .font(.hkBody)
            Text("Fillers, spoken corrections and your rules, fixed on this Mac.")
                .font(.hkCaption)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var wordsCard: some View {
        InsightCard {
            HStack(alignment: .top) {
                Metric(value: ledger.totalWords.formatted(), label: "Total words dictated")
                Spacer(minLength: Theme.s2)
                if let change = ledger.monthChange() {
                    Label(change.formatted(.percent.precision(.fractionLength(0))) + " this month",
                          systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.hkMeta.weight(.medium))
                        .foregroundStyle(Theme.signal)
                        .padding(.horizontal, Theme.s2)
                        .padding(.vertical, Theme.s1)
                        .background(Capsule().fill(Theme.signalSoft))
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text(bookComparison).font(.hkBody).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bookComparison: String {
        let words = ledger.totalWords
        let books = Double(words) / Double(UsageLedger.wordsPerBook)
        if books >= 1 { return "That's about \(books.formatted(.number.precision(.fractionLength(0...1)))) novels' worth." }
        let pages = words / 300
        return pages >= 1 ? "That's about \(pages) page\(pages == 1 ? "" : "s") of a novel." : "Your first page is on its way."
    }

    private var categoriesCard: some View {
        let categories = ledger.categories
        return InsightCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Where you dictate").font(.display(22))
                Spacer()
                Text("\(categories.count) of \(UsageCategory.allCases.count) kinds".uppercased())
                    .font(.hkMeta.weight(.medium)).tracking(0.6).foregroundStyle(Theme.ink2)
            }
            if categories.isEmpty {
                Text("Shows up after your first dictation.").font(.hkCaption).foregroundStyle(Theme.ink2)
            }
            ForEach(Array(categories.enumerated()), id: \.element.category) { rank, item in
                CategoryBar(category: item.category, words: item.words, share: item.share,
                            emphasis: max(0.35, 1 - Double(rank) * 0.18))
            }
            Text("Older dictations, from before Insights, count as Other.")
                .font(.hkCaption).foregroundStyle(Theme.ink3)
        }
    }

    private var streakCard: some View {
        let streak = ledger.currentStreak()
        return InsightCard {
            HStack(alignment: .firstTextBaseline) {
                Text("\(streak) day streak").font(.display(22))
                Spacer()
                Text("Longest \(ledger.longestStreak()) days".uppercased())
                    .font(.hkMeta.weight(.medium)).tracking(0.6).foregroundStyle(Theme.ink2)
            }
            ActivityHeatmap(counts: ledger.dailyCounts(), weeks: 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.s1) {
                Text("Less").font(.hkMeta).foregroundStyle(Theme.ink2)
                ForEach([0.0, 0.3, 0.65, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(level == 0 ? Theme.hairline : Theme.ink.opacity(level))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.hkMeta).foregroundStyle(Theme.ink2)
            }
        }
    }
}

private struct InsightCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) { content }
            .padding(Theme.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.r2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r2, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

private struct Metric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(value).font(.display(28)).contentTransition(.numericText())
            Text(label.uppercased()).font(.hkMeta.weight(.medium)).tracking(0.8).foregroundStyle(Theme.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A half-circle gauge: hairline track, sage progress.
private struct PaceArc: View {
    var progress: Double

    var body: some View {
        ZStack {
            HalfCircle().stroke(Theme.hairline, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            HalfCircle().trim(from: 0, to: progress)
                .stroke(Theme.signal, style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }
        .animation(Theme.gentle, value: progress)
        .accessibilityHidden(true)
    }

    private struct HalfCircle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let radius = min(rect.width / 2, rect.height) - 6
            path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: radius,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            return path
        }
    }
}

private struct CategoryBar: View {
    var category: UsageCategory
    var words: Int
    var share: Double
    var emphasis: Double

    var body: some View {
        HStack(spacing: Theme.s3) {
            Image(systemName: category.symbol)
                .frame(width: 20)
                .foregroundStyle(Theme.ink2)
            GeometryReader { geo in
                let width = max(44, geo.size.width * share)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.signal.opacity(emphasis))
                    .frame(width: width)
                    .overlay {
                        Text(share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.hkMeta.weight(.semibold))
                            .foregroundStyle(Theme.inverseInk)
                    }
            }
            .frame(width: 180, height: 28)
            Text("\(words.formatted()) \(category.rawValue)".uppercased())
                .font(.hkMeta.weight(.medium))
                .tracking(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.rawValue): \(words) words, \(Int((share * 100).rounded())) percent")
    }
}
