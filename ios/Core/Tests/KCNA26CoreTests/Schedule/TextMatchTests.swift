import XCTest
@testable import KCNA26Core

/// TextMatch has no Kotlin test of its own (ScheduleIndexTest and SpeakerPickerTest cover it);
/// these pin the KDoc examples and the UTF-16 details of the Swift port.
final class TextMatchTests: XCTestCase {
    func testKDocExamples() {
        XCTAssertTrue(TextMatch.matchesAll(TextMatch.normalize("Filip Křepinský"), TextMatch.terms("krepinsky")))
        XCTAssertTrue(TextMatch.matchesAll(TextMatch.normalize("255 A–C"), TextMatch.terms("255 a-c")))
        XCTAssertTrue(TextMatch.matchesAll(TextMatch.normalize("Justin O’Leary"), TextMatch.terms("o'leary")))
        XCTAssertTrue(TextMatch.matchesAll(TextMatch.normalize("Maciek Różacki"), TextMatch.terms("ROZACKI")))
    }

    func testNormalizeStripsMarksAndFoldsLetters() {
        XCTAssertEqual("lodz strasse", TextMatch.normalize("Łódź Straße"))
        XCTAssertEqual("aeoe-th\"x\"", TextMatch.normalize("ÆŒ—Þ“X”"))
        XCTAssertEqual("", TextMatch.normalize(""))
        // Already decomposed input (NFD) normalises the same as composed input.
        XCTAssertEqual(TextMatch.normalize("Jos\u{E9}"), TextMatch.normalize("Jose\u{301}"))
        XCTAssertEqual("jose", TextMatch.normalize("Jose\u{301}"))
    }

    func testTermsSplitOnWhitespaceAndDropEmpties() {
        XCTAssertEqual(["eviction", "lucy"], TextMatch.terms("  Eviction   LUCY \n"))
        XCTAssertEqual([], TextMatch.terms("   "))
        XCTAssertEqual([], TextMatch.terms(""))
        // Kotlin trim() strips Unicode spaces too (NBSP, U+3000).
        XCTAssertEqual(["a"], TextMatch.terms("\u{3000}a\u{A0}"))
    }

    func testMatchesAllNeedsEveryTermAndComparesUtf16Units() {
        XCTAssertTrue(TextMatch.matchesAll("abc def", ["def", "ab"]))
        XCTAssertFalse(TextMatch.matchesAll("abc def", ["def", "x"]))
        XCTAssertTrue(TextMatch.matchesAll("abc", [])) // Kotlin `all` on an empty list
        XCTAssertTrue(TextMatch.matchesAll("abc", [""]))
        // A term matches inside a grapheme cluster as Kotlin's String.contains does (Swift's
        // Character-based contains would not).
        XCTAssertTrue(TextMatch.matchesAll("e\u{20DD}", ["e"]))
    }
}
