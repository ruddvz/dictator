import XCTest
@testable import Dictator

final class DictationSmartFormatterTests: XCTestCase {
    func testCurrencies() {
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("It costs twenty dollars and fifty cents."),
                       "It costs $20.50.")
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("Send twenty dollars."),
                       "Send $20.")
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("Pay 100 dollars."),
                       "Pay $100.")
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("Only fifty cents."),
                       "Only $0.50.")
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("A round of five million dollars."),
                       "A round of $5 million.")
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("Costs twenty euros or fifty pounds or one hundred yen."),
                       "Costs €20 or £50 or ¥100.")
    }

    func testPercentages() {
        XCTAssertEqual(DictationSmartFormatter.formatPercentages("We saw twenty percent growth."),
                       "We saw 20% growth.")
        XCTAssertEqual(DictationSmartFormatter.formatPercentages("Accuracy is fifty point five percent."),
                       "Accuracy is 50.5%.")
        XCTAssertEqual(DictationSmartFormatter.formatPercentages("Success rate is 100 percent."),
                       "Success rate is 100%.")
    }

    func testClockTimes() {
        XCTAssertEqual(DictationSmartFormatter.formatClockTimes("Let's meet at five thirty pm."),
                       "Let's meet at 5:30 PM.")
        XCTAssertEqual(DictationSmartFormatter.formatClockTimes("Call at 9 45 am."),
                       "Call at 9:45 AM.")
        XCTAssertEqual(DictationSmartFormatter.formatClockTimes("Doors open at ten am."),
                       "Doors open at 10 AM.")
        XCTAssertEqual(DictationSmartFormatter.formatClockTimes("Meet at twelve noon or twelve midnight."),
                       "Meet at 12:00 PM or 12:00 AM.")
    }

    func testUnits() {
        XCTAssertEqual(DictationSmartFormatter.formatUnits("It is twenty degrees celsius today."),
                       "It is 20°C today.")
        XCTAssertEqual(DictationSmartFormatter.formatUnits("Set to seventy degrees fahrenheit."),
                       "Set to 70°F.")
        XCTAssertEqual(DictationSmartFormatter.formatUnits("Downloaded ten gigabytes and five megabytes."),
                       "Downloaded 10 GB and 5 MB.")
        XCTAssertEqual(DictationSmartFormatter.formatUnits("Driving sixty miles per hour."),
                       "Driving 60 mph.")
    }

    func testDecimals() {
        XCTAssertEqual(DictationSmartFormatter.formatDecimals("Pi is approximately three point one four."),
                       "Pi is approximately 3.14.")
        XCTAssertEqual(DictationSmartFormatter.formatDecimals("Value is zero point five."),
                       "Value is 0.5.")
    }

    func testQuantitiesAndIdioms() {
        XCTAssertEqual(DictationSmartFormatter.formatQuantities("I ordered twenty five items."),
                       "I ordered 25 items.")
        XCTAssertEqual(DictationSmartFormatter.formatQuantities("Received one hundred and fifty pages."),
                       "Received 150 pages.")
        XCTAssertEqual(DictationSmartFormatter.formatQuantities("Year two thousand twenty six."),
                       "Year 2026.")
        // Idioms with 'one' should be preserved
        XCTAssertEqual(DictationSmartFormatter.format("This is one of the best ideas."),
                       "This is one of the best ideas.")
    }

    func testCJKSpacing() {
        XCTAssertEqual(DictationSmartFormatter.formatCJK("我 们 一 起 去 看 看 。"),
                       "我们一起去看看。")
        XCTAssertEqual(DictationSmartFormatter.formatCJK("今 天 天 气 很 好 ， 明 天 也 是 。"),
                       "今天天气很好，明天也是。")
    }

    func testCodeAndTerminalSanitization() {
        XCTAssertEqual(DictationSmartFormatter.formatCodeAndTerminal("“hello world” and ‘single’", isTerminal: false),
                       "\"hello world\" and 'single'")
        XCTAssertEqual(DictationSmartFormatter.formatCodeAndTerminal("run ls - la on / usr / bin", isTerminal: true),
                       "run ls -la on /usr/bin")
        XCTAssertEqual(DictationSmartFormatter.formatCodeAndTerminal("first line\nsecond line\nthird line", isTerminal: true),
                       "first line second line third line")
    }

    func testDynamicSnippetExpansion() {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let template = "Date: {date}, Time: {time}, ISO: {iso}"
        let expanded = DictationSnippetExpander.expandDynamicVariables(in: template, now: fixedDate)
        XCTAssertFalse(expanded.contains("{date}"))
        XCTAssertFalse(expanded.contains("{time}"))
        XCTAssertFalse(expanded.contains("{iso}"))
    }

    func testGlobalCurrencies() {
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("Pay fifty rupees."),
                       "Pay ₹50.")
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("Costs twenty canadian dollars."),
                       "Costs CA$20.")
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("Costs twenty australian dollars."),
                       "Costs A$20.")
        XCTAssertEqual(DictationSmartFormatter.formatCurrencies("Price is twenty swiss francs."),
                       "Price is CHF 20.")
    }

    func testEmails() {
        XCTAssertEqual(DictationSmartFormatter.formatEmails("Send to john dot doe at gmail dot com please."),
                       "Send to john.doe@gmail.com please.")
        XCTAssertEqual(DictationSmartFormatter.formatEmails("Email support at apple dot com for help."),
                       "Email support@apple.com for help.")
        XCTAssertEqual(DictationSmartFormatter.formatEmails("Reach me at john underscore doe at company dot org."),
                       "Reach me at john_doe@company.org.")
    }

    func testURLs() {
        XCTAssertEqual(DictationSmartFormatter.formatURLs("Visit https colon slash slash github dot com slash ruddvz."),
                       "Visit https://github.com/ruddvz.")
        XCTAssertEqual(DictationSmartFormatter.formatURLs("Check out www dot google dot com today."),
                       "Check out www.google.com today.")
        XCTAssertEqual(DictationSmartFormatter.formatURLs("Go to github dot com slash ruddvz slash dictator."),
                       "Go to github.com/ruddvz/dictator.")
    }

    func testDates() {
        XCTAssertEqual(DictationSmartFormatter.formatDates("Event is on July fourth twenty twenty six."),
                       "Event is on July 4, 2026.")
        XCTAssertEqual(DictationSmartFormatter.formatDates("Party on December twenty fifth."),
                       "Party on December 25th.")
        XCTAssertEqual(DictationSmartFormatter.formatDates("Starting January first."),
                       "Starting January 1st.")
    }

    func testOrdinals() {
        XCTAssertEqual(DictationSmartFormatter.formatOrdinals("This is the twenty first century."),
                       "This is the 21st century.")
        XCTAssertEqual(DictationSmartFormatter.formatOrdinals("He finished thirty second in line."),
                       "He finished 32nd in line.")
        XCTAssertEqual(DictationSmartFormatter.formatOrdinals("Our hundredth user registered."),
                       "Our 100th user registered.")
    }

    func testDynamicSnippetExpansionExtended() {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let template = "{year}/{month}/{day}/{weekday}/{uuid}"
        let expanded = DictationSnippetExpander.expandDynamicVariables(in: template, now: fixedDate)
        XCTAssertFalse(expanded.contains("{year}"))
        XCTAssertFalse(expanded.contains("{month}"))
        XCTAssertFalse(expanded.contains("{day}"))
        XCTAssertFalse(expanded.contains("{weekday}"))
        XCTAssertFalse(expanded.contains("{uuid}"))
        let parts = expanded.split(separator: "/")
        XCTAssertEqual(parts.count, 5)
        XCTAssertEqual(parts[0], "2023")
        XCTAssertEqual(parts[1], "November")
        XCTAssertEqual(parts[4].split(separator: "-").count, 5)
    }
}
