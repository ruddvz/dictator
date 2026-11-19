import XCTest
@testable import Dictator

final class VoiceProfileTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(day: Int = 2, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func entry(_ text: String, raw: String? = nil, hour: Int = 12, day: Int = 2,
                       duration: TimeInterval? = 10) -> DictationHistoryEntry {
        DictationHistoryEntry(createdAt: date(day: day, hour: hour), text: text, rawText: raw, duration: duration)
    }

    private func ledger(dictations: Int, words: Int = 10, seconds: Double? = 5) -> UsageLedger {
        var ledger = UsageLedger()
        for index in 0..<dictations {
            ledger.record(words: words, seconds: seconds, wordsCleaned: 0, category: .other,
                          at: date(day: 1 + index % 20, hour: 12), calendar: calendar)
        }
        return ledger
    }

    // MARK: Empty and zero

    func testEmptyHistoryIsLockedWithNothingComputed() {
        let profile = VoiceProfile(entries: [], ledger: UsageLedger(), calendar: calendar)
        XCTAssertEqual(profile.dictations, 0)
        XCTAssertNil(profile.wordsPerMinute)
        XCTAssertNil(profile.pace)
        XCTAssertEqual(profile.minutesSaved, 0)
        XCTAssertNil(profile.timeSavedText)
        XCTAssertNil(profile.peakHours)
        XCTAssertNil(profile.catchphrase)
        XCTAssertNil(profile.mostCorrected)
        XCTAssertEqual(profile.fillersRemoved, 0)
        XCTAssertTrue(profile.unlockedCards.isEmpty)
        XCTAssertEqual(profile.nextUnlock?.card, .pace)
        XCTAssertEqual(profile.nextUnlock?.remaining, VoiceProfile.firstUnlock)
    }

    func testZeroDurationGivesNoPaceAndNoTimeSaved() {
        let entries = (0..<12).map { _ in entry("hello there friend", duration: 0) }
        let profile = VoiceProfile(entries: entries, ledger: ledger(dictations: 12, seconds: 0), calendar: calendar)
        XCTAssertNil(profile.wordsPerMinute, "No measured microphone time means no pace")
        XCTAssertNil(profile.pace)
        XCTAssertEqual(profile.minutesSaved, 0, "Untimed words don't count as time saved")
        XCTAssertNil(profile.timeSavedText)
        XCTAssertTrue(profile.isUnlocked(.pace), "The card unlocks; the view says the pace needs timing")
    }

    func testUntimedDaysDontInflateTimeSaved() {
        var ledger = UsageLedger()
        ledger.record(words: 400, seconds: 120, wordsCleaned: 0, category: .other, at: date(day: 1, hour: 9), calendar: calendar)
        ledger.record(words: 4_000, seconds: nil, wordsCleaned: 0, category: .other, at: date(day: 2, hour: 9), calendar: calendar)
        // 400 / 40 = 10 min typing, minus 2 min speaking.
        XCTAssertEqual(VoiceProfile.minutesSaved(ledger: ledger), 8, accuracy: 0.001)
    }

    func testTimeSavedIsNeverNegative() {
        var ledger = UsageLedger()
        // 10 words over 5 minutes: slower than typing.
        ledger.record(words: 10, seconds: 300, wordsCleaned: 0, category: .other, at: date(hour: 9), calendar: calendar)
        XCTAssertEqual(VoiceProfile.minutesSaved(ledger: ledger), 0)
    }

    // MARK: Pace thresholds

    func testPaceThresholds() {
        XCTAssertEqual(VoiceProfile.Pace(wordsPerMinute: 1), .unhurried)
        XCTAssertEqual(VoiceProfile.Pace(wordsPerMinute: 99), .unhurried)
        XCTAssertEqual(VoiceProfile.Pace(wordsPerMinute: 100), .steady)
        XCTAssertEqual(VoiceProfile.Pace(wordsPerMinute: 129), .steady)
        XCTAssertEqual(VoiceProfile.Pace(wordsPerMinute: 130), .quick)
        XCTAssertEqual(VoiceProfile.Pace(wordsPerMinute: 159), .quick)
        XCTAssertEqual(VoiceProfile.Pace(wordsPerMinute: 160), .rapid)
        XCTAssertEqual(VoiceProfile.Pace(wordsPerMinute: 400), .rapid)
    }

    func testPaceComesFromLedger() {
        // 10 words in 5 s = 120 wpm.
        let profile = VoiceProfile(entries: [], ledger: ledger(dictations: 10), calendar: calendar)
        XCTAssertEqual(profile.wordsPerMinute, 120)
        XCTAssertEqual(profile.pace, .steady)
    }

    // MARK: Unlocking

    func testCardsUnlockStepByStep() {
        func profile(_ count: Int) -> VoiceProfile {
            VoiceProfile(entries: [], ledger: ledger(dictations: count), calendar: calendar)
        }
        XCTAssertTrue(profile(9).unlockedCards.isEmpty)
        XCTAssertEqual(profile(9).nextUnlock?.remaining, 1)
        XCTAssertEqual(profile(10).unlockedCards, [.pace])
        XCTAssertEqual(profile(10).nextUnlock?.card, .cleanup)
        XCTAssertEqual(profile(10).nextUnlock?.remaining, 10)
        XCTAssertEqual(profile(29).unlockedCards, [.pace, .cleanup])
        XCTAssertEqual(profile(30).unlockedCards, [.pace, .cleanup, .peakHours])
        XCTAssertEqual(profile(40).unlockedCards, VoiceProfile.Card.allCases)
        XCTAssertNil(profile(40).nextUnlock)
    }

    func testUnlockCountsHistoryWhenLedgerIsBehind() {
        let entries = (0..<10).map { _ in entry("hi") }
        let profile = VoiceProfile(entries: entries, ledger: UsageLedger(), calendar: calendar)
        XCTAssertEqual(profile.dictations, 10)
        XCTAssertTrue(profile.isUnlocked(.pace))
    }

    // MARK: Time saved text

    func testTimeSavedText() {
        XCTAssertNil(VoiceProfile.timeSavedText(minutes: 0))
        XCTAssertNil(VoiceProfile.timeSavedText(minutes: 0.9))
        XCTAssertNil(VoiceProfile.timeSavedText(minutes: .nan))
        XCTAssertEqual(VoiceProfile.timeSavedText(minutes: 1), "about 1 min saved")
        XCTAssertEqual(VoiceProfile.timeSavedText(minutes: 25.4), "about 25 min saved")
        XCTAssertEqual(VoiceProfile.timeSavedText(minutes: 59.6), "about 1 h saved")
        XCTAssertEqual(VoiceProfile.timeSavedText(minutes: 90), "about 1.5 h saved")
        XCTAssertEqual(VoiceProfile.timeSavedText(minutes: 118), "about 2 h saved")
        XCTAssertEqual(VoiceProfile.timeSavedText(minutes: 12.4 * 60), "about 12 h saved")
    }

    // MARK: Peak hours

    func testPeakHoursNeedEnoughHistory() {
        let dates = (0..<4).map { _ in date(hour: 7) }
        XCTAssertNil(VoiceProfile.peakHours(dates, calendar: calendar))
    }

    func testEarlyBird() {
        let dates = [6, 7, 7, 8, 8, 15].map { date(hour: $0) }
        let peak = VoiceProfile.peakHours(dates, calendar: calendar)
        XCTAssertEqual(peak?.startHour, 6)
        XCTAssertEqual(peak?.dictations, 5)
        XCTAssertEqual(peak?.timeOfDay, .earlyBird)
        XCTAssertEqual(peak?.label, "6 AM–9 AM")
    }

    func testNightOwlWrapsPastMidnight() {
        let dates = [23, 23, 0, 0, 1, 14].map { date(hour: $0) }
        let peak = VoiceProfile.peakHours(dates, calendar: calendar)
        XCTAssertEqual(peak?.startHour, 23)
        XCTAssertEqual(peak?.timeOfDay, .nightOwl)
        XCTAssertEqual(peak?.label, "11 PM–2 AM")
        XCTAssertEqual(peak?.share ?? 0, 5.0 / 6.0, accuracy: 0.001)
    }

    func testTimeOfDayBoundaries() {
        XCTAssertEqual(VoiceProfile.TimeOfDay(hour: 4), .nightOwl)
        XCTAssertEqual(VoiceProfile.TimeOfDay(hour: 5), .earlyBird)
        XCTAssertEqual(VoiceProfile.TimeOfDay(hour: 10), .earlyBird)
        XCTAssertEqual(VoiceProfile.TimeOfDay(hour: 11), .midday)
        XCTAssertEqual(VoiceProfile.TimeOfDay(hour: 17), .evening)
        XCTAssertEqual(VoiceProfile.TimeOfDay(hour: 21), .evening, "8–11 PM is evening, not night owl")
        XCTAssertEqual(VoiceProfile.TimeOfDay(hour: 22), .nightOwl)
        XCTAssertEqual(VoiceProfile.hourLabel(0), "midnight")
        XCTAssertEqual(VoiceProfile.hourLabel(12), "noon")
        XCTAssertEqual(VoiceProfile.hourLabel(13), "1 PM")
    }

    // MARK: Catchphrase

    func testCatchphrasePrefersLongerPhraseOnTie() {
        let texts = ["Let me know when you're free.", "Sounds good, let me know.",
                     "Let me know what you think.", "See you tomorrow."]
        XCTAssertEqual(VoiceProfile.catchphrase(texts), VoiceProfile.Count(text: "let me know", count: 3))
    }

    func testCatchphraseSkipsContractionsAndCapitalisesI() {
        XCTAssertNil(VoiceProfile.catchphrase(["I don't know.", "i don't", "I don't care"]),
                     "\"I don't\" is all function words")
        let phrase = VoiceProfile.catchphrase(["I think so.", "Well I think it works.", "I think we should."])
        XCTAssertEqual(phrase?.text, "I think")
        XCTAssertEqual(VoiceProfile.displayPhrase("i'm on it"), "I'm on it")
    }

    func testCatchphraseCountsDictationsNotRepeats() {
        let texts = ["sounds good sounds good sounds good", "ok", "fine"]
        XCTAssertNil(VoiceProfile.catchphrase(texts), "Three times in one dictation is still one dictation")
    }

    func testCatchphraseSkipsFunctionWordPhrases() {
        let texts = ["I think it is", "and it is done", "it is what it is"]
        XCTAssertNil(VoiceProfile.catchphrase(texts))
        XCTAssertNil(VoiceProfile.catchphrase([]))
    }

    // MARK: Cleanup

    func testFillersAndStuttersRemoved() {
        let entries = [
            entry("So I need to leave.", raw: "Um so I I need to uh leave."),
            entry("Thanks.", raw: "Thanks."),
            entry("No raw text kept."),
        ]
        let cleanup = VoiceProfile.cleanup(entries)
        XCTAssertEqual(cleanup.fillers, 3, "um, the repeated I, and uh")
        XCTAssertNil(cleanup.mostCorrected)
    }

    func testMostCorrectedWordIsTheFixedForm() {
        let entries = [
            entry("Deploy it to Kubernetes today.", raw: "Deploy it to cooper netties today."),
            entry("Kubernetes is down.", raw: "Cooper Nettie's is down."),
            entry("Ask Siobhan.", raw: "Ask shiv on."),
        ]
        let cleanup = VoiceProfile.cleanup(entries)
        XCTAssertEqual(cleanup.mostCorrected, VoiceProfile.Count(text: "Kubernetes", count: 2))
        XCTAssertEqual(cleanup.fillers, 0)
    }

    func testSelfCorrectionDeletionIsNotACorrectedWord() {
        let entries = [entry("Meet at 5 PM.", raw: "Meet at four PM no actually 5 PM.")]
        let cleanup = VoiceProfile.cleanup(entries)
        XCTAssertNil(cleanup.mostCorrected)
        XCTAssertEqual(cleanup.fillers, 1, "Only 'actually' is a filler; the dropped words were a correction")
    }

    func testGapsAlignment() {
        let gaps = VoiceProfile.gaps(["a", "b", "c"], ["a", "x", "c"])
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.deleted, [1])
        XCTAssertEqual(gaps.first?.inserted, [1])
        XCTAssertTrue(VoiceProfile.gaps([], []).isEmpty)
        XCTAssertEqual(VoiceProfile.gaps([], ["a"]).first?.inserted, [0])
    }
}
