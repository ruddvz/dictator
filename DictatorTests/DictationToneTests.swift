import XCTest
@testable import Dictator

final class DictationToneTests: XCTestCase {
    func testFormalLeavesTextAlone() {
        XCTAssertEqual(DictationTone.formal.apply(to: "Hello there. See you soon."), "Hello there. See you soon.")
    }

    func testCasualDropsOnlyTheFinalFullStop() {
        XCTAssertEqual(DictationTone.casual.apply(to: "Hello there. See you soon."), "Hello there. See you soon")
        XCTAssertEqual(DictationTone.casual.apply(to: "Wait for it..."), "Wait for it...")
        XCTAssertEqual(DictationTone.casual.apply(to: "Are you in?"), "Are you in?")
    }

    func testVeryCasualLowercasesAndDropsFullStops() {
        XCTAssertEqual(DictationTone.veryCasual.apply(to: "Hey, are we still on? I'm running late. Sorry."),
                       "hey, are we still on? I'm running late sorry")
    }

    func testVeryCasualKeepsAcronymsDecimalsAndEllipses() {
        XCTAssertEqual(DictationTone.veryCasual.apply(to: "NASA launched at 3.5 km. Then... Wow!"),
                       "NASA launched at 3.5 km then... wow!")
    }

    func testContextsComeFromTheBundleIdentifier() {
        XCTAssertEqual(DictationContext.context(for: "com.apple.MobileSMS"), .personal)
        XCTAssertEqual(DictationContext.context(for: "net.whatsapp.WhatsApp"), .personal)
        XCTAssertEqual(DictationContext.context(for: "com.tinyspeck.slackmacgap"), .work)
        XCTAssertEqual(DictationContext.context(for: "com.microsoft.teams2"), .work)
        XCTAssertEqual(DictationContext.context(for: "com.apple.mail"), .email)
        XCTAssertEqual(DictationContext.context(for: "com.microsoft.Outlook"), .email)
        XCTAssertEqual(DictationContext.context(for: "com.apple.Notes"), .other)
        XCTAssertEqual(DictationContext.context(for: nil), .other)
    }

    func testSettingsDefaultToFormalAndNeverRestyleCode() {
        var settings = DictationToneSettings()
        XCTAssertEqual(settings.tone(forBundle: "com.apple.MobileSMS", mode: .message), .formal)
        settings.tones[.personal] = .veryCasual
        XCTAssertEqual(settings.tone(forBundle: "com.apple.MobileSMS", mode: .message), .veryCasual)
        XCTAssertEqual(settings.tone(forBundle: "com.apple.MobileSMS", mode: .code), .formal)
    }

    func testProcessorAppliesToneButNotToCode() {
        let casual = DictationTranscriptProcessor.process("Sounds good. See you there.", mode: .natural,
                                                          snippets: "", tone: .veryCasual)
        XCTAssertEqual(casual, "sounds good see you there")
        let code = DictationTranscriptProcessor.process("Sounds good.", mode: .code, snippets: "", tone: .veryCasual)
        XCTAssertEqual(code, DictationTranscriptProcessor.process("Sounds good.", mode: .code, snippets: ""))
    }
}
