import SwiftUI

/// Lifetime numbers from the local usage ledger: pace, cleanup, words, where you dictate and
/// your streak. Counts only; everything stays on this Mac.
struct InsightsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    private var ledger: UsageLedger { model.usageLedger }

    private var subtitle: String {
        let base = "Counted from finished dictations and kept by day, on this Mac."
        guard ledger.totalDictations == 0 else { return base }
        return base + (model.savesDictationHistory
                       ? " Finish a dictation and your numbers start here."
                       : " Insights are recorded only while saving history is on in Settings.")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                PageHeader(eyebrow: "", title: "Insights", subtitle: subtitle)
                VStack(alignment: .leading, spacing: Theme.s3) {
                    figureRow
                    if ledger.totalWords > 0 {
                        Text(summaryLine)
                            .font(.hkCallout)
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .reveal(1)
                streakCard.reveal(2)
                VoiceProfileSection(profile: VoiceProfile(entries: model.dictationHistory, ledger: ledger),
                                    savesHistory: model.savesDictationHistory)
                    .reveal(3)
                categoriesCard.reveal(4)
                if ledger.totalDictations > 0 {
                    Button("Reset insights…") { confirmReset = true }
                        .buttonStyle(.plain)
                        .font(.hkCaption)
                        .foregroundStyle(Theme.ink2)
                        .confirmationDialog("Reset insights?", isPresented: $confirmReset) {
                            Button("Reset", role: .destructive) { model.resetUsageInsights() }
                        } message: {
                            Text("Clears these totals and your streak. History is not changed.")
                        }
                }
            }
            .pageLayout(maxWidth: Theme.homeWidth)
        }
    }

    // MARK: Figures

    /// One row of figures, number over label, split by hairlines. No cards, no gauge.
    private var figureRow: some View {
        let wpm = ledger.wordsPerMinute ?? 0
        let ratio = Double(wpm) / Double(UsageLedger.typingWordsPerMinute)
        return HStack(alignment: .top, spacing: Theme.s5) {
            Metric(value: ledger.totalWords.formatted(), label: wordsLabel, isLead: true)
            figureDivider
            Metric(value: ledger.totalDictations.formatted(), label: ledger.totalDictations == 1 ? "Dictation" : "Dictations")
            figureDivider
            Metric(value: wpm == 0 ? "–" : wpm.formatted(), label: "Words per minute")
            figureDivider
            Metric(value: wpm == 0 ? "–" : ratio.formatted(.number.precision(.fractionLength(1))) + "×",
                   label: "Typing speed")
                .help("Compared with typing at about \(UsageLedger.typingWordsPerMinute) words per minute")
            figureDivider
            Metric(value: ledger.wordsCleaned.formatted(), label: "Words cleaned up")
                .help("Fillers, spoken corrections and your rules, fixed on this Mac.")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var figureDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1).frame(maxHeight: .infinity)
    }

    private var wordsLabel: String {
        guard let change = ledger.monthChange() else { return "Words dictated" }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        return "Words dictated, \(change >= 0 ? "up" : "down") \(percent) this month"
    }

    private var summaryLine: String {
        guard let saved = VoiceProfile.timeSavedText(minutes: VoiceProfile.minutesSaved(ledger: ledger)) else {
            return bookComparison
        }
        return bookComparison + " Compared with typing, " + saved + "."
    }

    private var bookComparison: String {
        let words = ledger.totalWords
        let books = Double(words) / Double(UsageLedger.wordsPerBook)
        if books >= 1 { return "That's about \(books.formatted(.number.precision(.fractionLength(0...1)))) novels' worth." }
        let pages = words / 300
        return pages >= 1 ? "That's about \(pages) page\(pages == 1 ? "" : "s") of a novel." : "Your first page is on its way."
    }

    // MARK: Cards

    private var categoriesCard: some View {
        let categories = ledger.categories
        return InsightCard {
            HStack(alignment: .firstTextBaseline) {
                Text("Where you dictate").font(.display(22))
                Spacer()
                if !categories.isEmpty {
                    Text("\(categories.count) of \(UsageCategory.allCases.count) kinds")
                        .font(.hkCaption.monospacedDigit()).foregroundStyle(Theme.ink2)
                }
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
                    .font(.hkCaption).foregroundStyle(Theme.ink2)
            }
        }
    }

    private var streakCard: some View {
        let streak = ledger.currentStreak()
        let longest = ledger.longestStreak()
        return InsightCard {
            HStack(alignment: .firstTextBaseline) {
                Metric(value: streak.formatted(), label: "Day streak")
                Spacer()
                if longest > 0 {
                    Text("Longest \(longest) day\(longest == 1 ? "" : "s")")
                        .font(.hkCaption.monospacedDigit()).foregroundStyle(Theme.ink2)
                }
            }
            // As many weeks as the width holds, up to a year.
            GeometryReader { geo in
                InsightsHeatmap(counts: ledger.dailyCounts(), weeks: InsightsHeatmap.weeks(fitting: geo.size.width))
            }
            .frame(height: InsightsHeatmap.height)
            HStack(spacing: Theme.s1) {
                Spacer()
                Text("Less").font(.hkMeta).foregroundStyle(Theme.ink2)
                ForEach(0..<InsightsHeatmap.levels.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(InsightsHeatmap.fill(level: index))
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(index == 0 ? Theme.hairline : Color.clear, lineWidth: 1))
                        .frame(width: 12, height: 12)
                }
                Text("More").font(.hkMeta).foregroundStyle(Theme.ink2)
            }
            .accessibilityHidden(true)
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
                if !profile.unlockedCards.isEmpty {
                    Text("\(profile.unlockedCards.count) of \(VoiceProfile.Card.allCases.count) cards")
                        .font(.hkCaption.monospacedDigit()).foregroundStyle(Theme.ink2)
                }
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
                    .font(.hkCaption).foregroundStyle(Theme.ink2)
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
                    .font(.hkCaption.monospacedDigit()).foregroundStyle(Theme.ink2)
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
                .foregroundStyle(Theme.ink2)
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

/// A figure: a big New York number over a small label. The lead figure carries a short sage rule.
private struct Metric: View {
    var value: String
    var label: String
    var isLead = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(value)
                .font(.display(36).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if isLead {
                Capsule().fill(Theme.signal).frame(width: 32, height: 3)
                    .padding(.bottom, Theme.s1)
                    .accessibilityHidden(true)
            }
            Text(label).font(.hkCaption).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The page's signature: a year of days, one sage cell per day, deeper the more you dictated.
/// Empty days are sunk to the window's paper tone with a hairline edge, so they read in light and dark.
private struct InsightsHeatmap: View {
    static let cell: CGFloat = 15
    static let gap: CGFloat = 4
    static let height = cell * 7 + gap * 6

    static func weeks(fitting width: CGFloat) -> Int {
        max(8, min(53, Int((width + gap) / (cell + gap))))
    }
    /// Sage strengths for 1–4 activity levels; level 0 is the empty cell.
    static let levels: [Double] = [0, 0.35, 0.6, 0.8, 1.0]

    var counts: [Date: Int]
    var weeks: Int
    var now = Date()

    static func fill(level: Int) -> AnyShapeStyle {
        level == 0 ? AnyShapeStyle(Theme.paper) : AnyShapeStyle(Theme.signal.opacity(levels[min(level, levels.count - 1)]))
    }

    private static func level(count: Int, max maxCount: Int) -> Int {
        guard count > 0 else { return 0 }
        let steps = Double(levels.count - 1)
        return max(1, min(levels.count - 1, Int((Double(count) / Double(maxCount) * steps).rounded(.up))))
    }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekdayOffset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let lastColumnStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today) ?? today
        let maxCount = max(1, counts.values.max() ?? 1)

        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(0..<weeks, id: \.self) { column in
                VStack(spacing: Self.gap) {
                    ForEach(0..<7, id: \.self) { row in
                        let start = calendar.date(byAdding: .day, value: (column - weeks + 1) * 7, to: lastColumnStart) ?? today
                        let day = calendar.date(byAdding: .day, value: row, to: start) ?? today
                        let count = counts[day] ?? 0
                        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
                        Group {
                            if day > today {
                                shape.fill(Color.clear)
                            } else {
                                shape.fill(Self.fill(level: Self.level(count: count, max: maxCount)))
                                    .overlay(shape.strokeBorder(count == 0 ? Theme.hairline : Color.clear, lineWidth: 1))
                            }
                        }
                        .frame(width: Self.cell, height: Self.cell)
                        .help(day > today ? "" : "\(day.formatted(date: .abbreviated, time: .omitted)): \(count) dictation\(count == 1 ? "" : "s")")
                        .accessibilityElement()
                        .accessibilityHidden(day > today)
                        .accessibilityLabel("\(day.formatted(date: .long, time: .omitted)): \(count) dictation\(count == 1 ? "" : "s")")
                    }
                }
                .reveal(column / 4, distance: 4) // the weeks fill in left to right
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation activity for the last \(weeks) weeks")
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
            HStack(spacing: Theme.s2) {
                Text(category.rawValue).foregroundStyle(Theme.ink2)
                Spacer(minLength: 0)
                Text(words.formatted()).monospacedDigit().foregroundStyle(Theme.ink2)
            }
            .font(.hkCaption)
            .lineLimit(1)
            .frame(width: 128)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.rawValue): \(words) words, \(Int((share * 100).rounded())) percent")
    }
}
