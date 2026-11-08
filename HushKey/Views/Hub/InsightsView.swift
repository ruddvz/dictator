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
                           subtitle: "Counted from finished dictations and kept by day, on this Mac.")
                if ledger.totalDictations == 0 {
                    Text(model.savesDictationHistory
                         ? "Finish a dictation and your numbers start here."
                         : "Insights are recorded only while saving history is on in Settings.")
                        .font(.hkCallout)
                        .foregroundStyle(Theme.ink2)
                }
                HStack(alignment: .top, spacing: Theme.s4) {
                    speedCard.reveal(1)
                    cleanupCard.reveal(2)
                    wordsCard.reveal(3)
                }
                .fixedSize(horizontal: false, vertical: true)
                VoiceProfileSection(profile: VoiceProfile(entries: model.dictationHistory, ledger: ledger),
                                    savesHistory: model.savesDictationHistory)
                    .reveal(4)
                HStack(alignment: .top, spacing: Theme.s4) {
                    categoriesCard.reveal(4)
                    streakCard.reveal(5)
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
            Metric(value: wpm == 0 ? "–" : wpm.formatted(), label: "Words per minute")
            Rectangle().fill(Theme.hairline).frame(height: 1)
            // The ratio sits on the arc's baseline, inside the half circle.
            ZStack(alignment: .bottom) {
                PaceArc(progress: min(1, Double(wpm) / 200))
                    .frame(width: 150, height: 80)
                VStack(spacing: 0) {
                    Text(wpm == 0 ? "–" : ratio.formatted(.number.precision(.fractionLength(1))) + "×")
                        .font(.hkTitle2)
                    Text("typing speed").font(.hkCaption).foregroundStyle(Theme.ink2)
                }
            }
            .frame(maxWidth: .infinity)
            .help("Compared with typing at about \(UsageLedger.typingWordsPerMinute) words per minute")
            if let saved = VoiceProfile.timeSavedText(minutes: VoiceProfile.minutesSaved(ledger: ledger)) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                Label(saved.prefix(1).uppercased() + saved.dropFirst() + " vs typing", icon: .clock)
                    .hushIconSize(14)
                    .font(.hkCallout.weight(.medium))
                    .foregroundStyle(Theme.ink2)
                    .help("Words at \(VoiceProfile.typingWordsPerMinute) wpm typing, minus the time you spent speaking")
            }
        }
    }

    private var cleanupCard: some View {
        InsightCard {
            Metric(value: ledger.wordsCleaned.formatted(), label: "Words cleaned up")
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text("across \(ledger.totalDictations.formatted()) dictation\(ledger.totalDictations == 1 ? "" : "s")")
                .font(.hkBody)
                .foregroundStyle(Theme.ink2)
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
                          icon: change >= 0 ? .arrowUpRight : .arrowDownRight)
                        .font(.hkMeta.weight(.medium))
                        .foregroundStyle(change >= 0 ? Theme.signal : Theme.ink2)
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
                Text("\(categories.count) of \(UsageCategory.allCases.count) kinds")
                    .font(.hkMeta.weight(.medium)).foregroundStyle(Theme.ink2)
            }
            if categories.isEmpty {
                Text("Shows up after your first dictation.").font(.hkCaption).foregroundStyle(Theme.ink2)
            }
            ForEach(Array(categories.enumerated()), id: \.element.category) { rank, item in
                CategoryBar(category: item.category, words: item.words, share: item.share,
                            emphasis: max(0.35, 1 - Double(rank) * 0.18))
            }
            if !categories.isEmpty {
                Text("Older dictations, from before Insights, count as Other.")
                    .font(.hkCaption).foregroundStyle(Theme.ink3)
            }
        }
    }

    private var streakCard: some View {
        let streak = ledger.currentStreak()
        return InsightCard {
            HStack(alignment: .firstTextBaseline) {
                Text("\(streak) day streak").font(.display(22))
                Spacer()
                Text("Longest \(ledger.longestStreak()) days")
                    .font(.hkMeta.weight(.medium)).foregroundStyle(Theme.ink2)
            }
            ActivityHeatmap(counts: ledger.dailyCounts(), weeks: 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.s1) {
                Text("Less").font(.hkMeta).foregroundStyle(Theme.ink2)
                ForEach([0.0, 0.3, 0.65, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(level == 0 ? Theme.hairline : Theme.signal.opacity(0.3 + 0.7 * level))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.hkMeta).foregroundStyle(Theme.ink2)
            }
        }
    }
}

/// "Your voice": cards that unlock one at a time, with an honest count before the first.
private struct VoiceProfileSection: View {
    var profile: VoiceProfile
    var savesHistory: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your voice").font(.display(22))
                Spacer()
                Text("\(profile.unlockedCards.count) of \(VoiceProfile.Card.allCases.count) cards")
                    .font(.hkMeta.weight(.medium)).foregroundStyle(Theme.ink2)
            }
            if profile.unlockedCards.isEmpty {
                lockedIntro
            } else {
                let columns = [GridItem(.flexible(), spacing: Theme.s4, alignment: .top),
                               GridItem(.flexible(), spacing: Theme.s4, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.s4) {
                    ForEach(VoiceProfile.Card.allCases, id: \.self) { card in
                        if profile.isUnlocked(card) { VoiceTile(title: card.title) { content(card) } }
                        else { LockedTile(card: card, remaining: card.unlocksAt - profile.dictations) }
                    }
                }
                Text("Read from your last \(profile.historyCount) saved dictation\(profile.historyCount == 1 ? "" : "s") on this Mac.")
                    .font(.hkCaption).foregroundStyle(Theme.ink3)
            }
        }
    }

    private var lockedIntro: some View {
        let done = min(profile.dictations, VoiceProfile.firstUnlock)
        return InsightCard {
            Text(savesHistory
                 ? "After \(VoiceProfile.firstUnlock) dictations, HushKey sketches how you talk: your pace, what cleanup fixes, when you talk most and the phrase you say most. It's read from the history on this Mac and goes nowhere else."
                 : "Your voice is read from the history on this Mac. Turn on saving history in Settings to build it.")
                .font(.hkBody)
                .fixedSize(horizontal: false, vertical: true)
            if savesHistory {
                ProgressStrip(progress: Double(done) / Double(VoiceProfile.firstUnlock))
                Text("\(done) of \(VoiceProfile.firstUnlock) dictations so far")
                    .font(.hkCaption).foregroundStyle(Theme.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func content(_ card: VoiceProfile.Card) -> some View {
        switch card {
        case .pace:
            if let pace = profile.pace, let wpm = profile.wordsPerMinute {
                headline(pace.rawValue, detail: "\(wpm) words a minute. \(pace.detail)")
            } else {
                headline("Not measured yet", detail: "Pace needs dictations with recorded microphone time.")
            }
        case .cleanup:
            headline("\(profile.fillersRemoved.formatted()) filler\(profile.fillersRemoved == 1 ? "" : "s") removed",
                     detail: profile.mostCorrected.map { "Fixed most often: \($0.text), \(times($0.count))." }
                        ?? "No word has needed fixing yet.")
        case .peakHours:
            if let peak = profile.peakHours {
                headline(peak.timeOfDay.rawValue,
                         detail: "Most often \(peak.label), \(peak.share.formatted(.percent.precision(.fractionLength(0)))) of your dictations.")
            } else {
                headline("Not enough yet", detail: "Shows once there are \(VoiceProfile.minimumForPeakHours) dictations in history.")
            }
        case .phrase:
            if let phrase = profile.catchphrase {
                headline("“\(phrase.text)”", detail: "In \(phrase.count) of your last \(profile.historyCount) dictations.")
            } else {
                headline("Nothing repeats yet",
                         detail: "A phrase shows here once it's in \(VoiceProfile.minimumPhraseDictations) dictations.")
            }
        }
    }

    private func headline(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(title).font(.display(22)).lineLimit(2)
            Text(detail).font(.hkCallout).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func times(_ count: Int) -> String { count == 1 ? "once" : count == 2 ? "twice" : "\(count) times" }
}

private struct VoiceTile<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        InsightCard {
            SectionLabel(title: title)
            content
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LockedTile: View {
    var card: VoiceProfile.Card
    var remaining: Int

    var body: some View {
        InsightCard {
            SectionLabel(title: card.title)
            Label("In \(remaining) more dictation\(remaining == 1 ? "" : "s")", icon: .lock)
                .hushIconSize(14)
                .font(.hkCallout)
                .foregroundStyle(Theme.ink3)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A thin hairline track with a sage fill.
private struct ProgressStrip: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(Theme.signal).frame(width: max(6, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
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
            Text(label).font(.hkCallout).foregroundStyle(Theme.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A half-circle gauge: hairline track, sage progress.
/// Typing-pace gauge; the sage arc sweeps up to the pace when the page opens.
private struct PaceArc: View {
    var progress: Double
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            HalfCircle().stroke(Theme.hairline, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            HalfCircle().trim(from: 0, to: shown)
                .stroke(Theme.signal, style: StrokeStyle(lineWidth: 12, lineCap: .round))
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.2)) { shown = progress } }
        .onChange(of: progress) { _, new in withAnimation(Theme.gentle) { shown = new } }
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
    @State private var grown = false

    var body: some View {
        HStack(spacing: Theme.s3) {
            SymbolGlyph(category.symbol, size: 18)
                .frame(width: 20)
                .foregroundStyle(Theme.ink2)
            // The bar is a share of its full-width track, so 100 % fills the track.
            GeometryReader { geo in
                let width = max(44, geo.size.width * share)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.signal.opacity(emphasis))
                    .frame(width: grown ? width : 44)
                    .overlay {
                        Text(share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.hkMeta.weight(.semibold))
                            .foregroundStyle(Theme.inverseInk)
                    }
            }
            .frame(height: 28)
            .background(Theme.hairline.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.86).delay(0.25)) { grown = true } }
            Text("\(category.rawValue) · \(words.formatted())")
                .font(.hkMeta.weight(.medium))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 120, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.rawValue): \(words) words, \(Int((share * 100).rounded())) percent")
    }
}
