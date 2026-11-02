import XCTest
@testable import HushKey

final class UsageLedgerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testRecordAddsUpDaysAndCategories() {
        var ledger = UsageLedger()
        ledger.record(words: 30, seconds: 15, wordsCleaned: 2, category: .work, at: day(2026, 11, 2), calendar: calendar)
        ledger.record(words: 10, seconds: 5, wordsCleaned: 1, category: .email, at: day(2026, 11, 2, hour: 18), calendar: calendar)
        ledger.record(words: 0, seconds: 5, wordsCleaned: 0, category: .work, at: day(2026, 11, 3), calendar: calendar)

        XCTAssertEqual(ledger.days.count, 1, "Empty dictations are not counted")
        XCTAssertEqual(ledger.totalWords, 40)
        XCTAssertEqual(ledger.totalDictations, 2)
        XCTAssertEqual(ledger.wordsCleaned, 3)
        XCTAssertEqual(ledger.wordsPerMinute, 120)
        XCTAssertEqual(ledger.categories.map(\.category), [.work, .email])
        XCTAssertEqual(ledger.categories.first?.share ?? 0, 0.75, accuracy: 0.001)
    }

    func testWordsPerMinuteNeedsTimedDays() {
        var ledger = UsageLedger()
        ledger.record(words: 50, seconds: nil, wordsCleaned: 0, category: .other, at: day(2026, 11, 2), calendar: calendar)
        XCTAssertNil(ledger.wordsPerMinute)
    }

    func testStreaksCountConsecutiveDays() {
        var ledger = UsageLedger()
        for date in [day(2026, 10, 1), day(2026, 10, 2), day(2026, 10, 3), day(2026, 10, 4),
                     day(2026, 11, 1), day(2026, 11, 2)] {
            ledger.record(words: 5, seconds: 2, wordsCleaned: 0, category: .other, at: date, calendar: calendar)
        }
        XCTAssertEqual(ledger.longestStreak(calendar: calendar), 4)
        XCTAssertEqual(ledger.currentStreak(now: day(2026, 11, 2), calendar: calendar), 2)
        XCTAssertEqual(ledger.currentStreak(now: day(2026, 11, 3), calendar: calendar), 2, "Today can still continue it")
        XCTAssertEqual(ledger.currentStreak(now: day(2026, 11, 4), calendar: calendar), 0)
    }

    func testMonthChangeComparesWithLastMonth() {
        var ledger = UsageLedger()
        ledger.record(words: 100, seconds: 30, wordsCleaned: 0, category: .other, at: day(2026, 10, 10), calendar: calendar)
        XCTAssertNil(ledger.monthChange(now: day(2026, 10, 20), calendar: calendar))
        ledger.record(words: 150, seconds: 30, wordsCleaned: 0, category: .other, at: day(2026, 11, 2), calendar: calendar)
        XCTAssertEqual(ledger.monthChange(now: day(2026, 11, 2), calendar: calendar) ?? 0, 0.5, accuracy: 0.001)
    }

    func testFirstOfTheMonthCountsOnlyInItsOwnMonth() {
        var ledger = UsageLedger()
        ledger.record(words: 40, seconds: 10, wordsCleaned: 0, category: .other, at: day(2026, 11, 1), calendar: calendar)
        XCTAssertNil(ledger.monthChange(now: day(2026, 11, 2), calendar: calendar), "October has no words")
    }

    func testWordsCleanedCountsRemovedAndChangedWords() {
        XCTAssertEqual(UsageLedger.wordsCleaned(raw: "um so I think uh we should go", final: "So I think we should go."), 2)
        XCTAssertEqual(UsageLedger.wordsCleaned(raw: "meet at two no three", final: "Meet at three."), 2)
        XCTAssertEqual(UsageLedger.wordsCleaned(raw: "Hello there", final: "Hello there."), 0)
    }

    func testSeededFromHistoryCountsAsOther() {
        let entries = [
            DictationHistoryEntry(createdAt: day(2026, 11, 1), text: "Hello there friend.", rawText: "um hello there friend", duration: 3),
            DictationHistoryEntry(createdAt: day(2026, 11, 2), text: "See you soon.")
        ]
        let ledger = UsageLedger.seeded(from: entries, calendar: calendar)
        XCTAssertEqual(ledger.totalDictations, 2)
        XCTAssertEqual(ledger.totalWords, 6)
        XCTAssertEqual(ledger.wordsCleaned, 1)
        XCTAssertEqual(ledger.categories.map(\.category), [.other])
    }

    func testCategoryFollowsModeAndApp() {
        XCTAssertEqual(UsageCategory.category(mode: .code, bundleIdentifier: "com.apple.mail"), .code)
        XCTAssertEqual(UsageCategory.category(mode: .natural, bundleIdentifier: "com.apple.mail"), .email)
        XCTAssertEqual(UsageCategory.category(mode: .natural, bundleIdentifier: "com.tinyspeck.slackmacgap"), .work)
        XCTAssertEqual(UsageCategory.category(mode: .natural, bundleIdentifier: nil), .other)
    }

    func testLedgerRoundTripsThroughTheArchive() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "usage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var ledger = UsageLedger()
        ledger.record(words: 12, seconds: 4, wordsCleaned: 1, category: .personal, at: day(2026, 11, 2), calendar: calendar)
        try UsageLedgerStore.save(ledger, to: url)
        XCTAssertEqual(UsageLedgerStore.load(from: url), ledger)
    }

    func testLanguageSearchMatchesNamesAndIdentifier() {
        let german = DictationLanguage(identifier: "de-DE", name: "German (Germany)")
        XCTAssertTrue(german.matches("germ"))
        XCTAssertTrue(german.matches("Deutsch"))
        XCTAssertTrue(german.matches("de-de"))
        XCTAssertTrue(german.matches("  "))
        XCTAssertFalse(german.matches("French"))
    }
}
