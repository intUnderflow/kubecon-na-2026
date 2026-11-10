import XCTest
@testable import KCNA26Core

/// KRegex: Kotlin Regex semantics over NSRegularExpression (UTF-16 offsets).
final class KRegexTests: XCTestCase {

    func testMatchesIsWholeInput() {
        let safe = KRegex("^[a-z0-9][a-z0-9_-]*\\.json$")
        XCTAssertTrue(safe.matches("schedule.json"))
        XCTAssertFalse(safe.matches("../schedule.json"))
        let r = KRegex("a|ab")
        XCTAssertTrue(r.matches("ab")) // backtracks to the alternative that covers the input
        XCTAssertFalse(r.matches("abc"))
        XCTAssertTrue(r.containsMatchIn("xxab"))
        XCTAssertTrue(KRegex("\\d{1,12}").matches("1289955"))
        XCTAssertFalse(KRegex("\\d{1,12}").matches("m1289955"))
        XCTAssertTrue(KRegex("a.b", options: .literal).matches("a.b"))
        XCTAssertFalse(KRegex("a.b", options: .literal).matches("axb"))
    }

    func testFindAndGroupsUseUTF16Offsets() throws {
        let r = KRegex("(b)(x)?(c)")
        let m = try XCTUnwrap(r.find("😀abc"))
        XCTAssertEqual(m.value, "bc")
        XCTAssertEqual(m.range, 3..<5) // 😀 is two UTF-16 units
        XCTAssertEqual(m.groupValues, ["bc", "b", "", "c"])
        XCTAssertEqual(m.groups, ["bc", "b", nil, "c"])
        XCTAssertNil(m.groupRanges[2])
        XCTAssertNil(r.find("😀abc", startIndex: 4))
        XCTAssertEqual(KRegex("o").findAll("foo boo").map(\.range.lowerBound), [1, 2, 5, 6])
        let named = try XCTUnwrap(KRegex("(?<h>\\d+):(?<m>\\d{2})").find("at 9:05"))
        XCTAssertEqual(named.group(named: "h"), "9")
        XCTAssertEqual(named.group(named: "m"), "05")
        XCTAssertNil(named.group(named: "nope"))
    }

    func testReplace() {
        XCTAssertEqual(KRegex("[\\s]*[-–—]+\\s*$").replace("Panel – ", ""), "Panel")
        XCTAssertEqual(KRegex("(\\w+)@(\\w+)").replace("a@b c@d", "$2.$1"), "b.a d.c")
        XCTAssertEqual(KRegex("\\d+").replace("a1b22c", transform: { "<\($0.value.count)>" }), "a<1>b<2>c")
        XCTAssertEqual(KRegex("x").replace("abc", transform: { _ in "!" }), "abc")
        XCTAssertEqual(KRegex("o").replaceFirst("foo", "0"), "f0o")
        XCTAssertEqual(KRegex("\\p{Mn}+").replace("e\u{301}cole".decomposedStringWithCanonicalMapping, ""), "ecole")
        XCTAssertEqual(KRegex(" (?:to|on) Level \\d+(?=,|$)").replace("Take the escalator up to Level 2", ""), "Take the escalator up")
        XCTAssertEqual(KRegex("^(☕|🍲)\\uFE0F?\\s*").replace("☕️ Coffee Break", ""), "Coffee Break")
    }

    func testReplacementUsesJavaSyntax() {
        // Java Matcher.appendReplacement, checked against JDK 21 "...".replaceAll(...).
        let hm = KRegex("(?<h>\\d+):(?<m>\\d+)")
        XCTAssertEqual(hm.replace("9:05", "${m}h${h}"), "05h9")
        XCTAssertEqual(hm.replaceFirst("9:05 and 10:30", "${m}h${h}"), "05h9 and 10:30")
        XCTAssertEqual(hm.replace("9:05", "$2h$1 ($0)"), "05h9 (9:05)")
        XCTAssertEqual(hm.replace("9:05", "\\$1 \\\\ \\x"), "$1 \\ x") // backslash quotes the next char
        // "$12": group 12 if it exists, else group 1 then "2".
        XCTAssertEqual(KRegex("(a)").replace("a", "$12"), "a2")
        let twelve = KRegex(String(repeating: "(.)", count: 12))
        XCTAssertEqual(twelve.replace("abcdefghijkl", "$12$1"), "la")
        XCTAssertEqual(twelve.replace("abcdefghijkl", "$13"), "a3")
        // An unmatched group adds nothing.
        XCTAssertEqual(KRegex("(x)?b").replace("ab", "[$1]"), "a[]")
        XCTAssertEqual(KRegex("(?<x>x)?b").replace("ab", "[${x}]"), "a[]")
        // Without a match the replacement is not examined (Java does not throw then either).
        XCTAssertEqual(KRegex("x").replace("abc", "$"), "abc")
        XCTAssertEqual(KRegex("x").replaceFirst("abc", "${nope}"), "abc")
        // Regex.escapeReplacement.
        XCTAssertEqual(KRegex.escapeReplacement("a$1\\b"), "a\\$1\\\\b")
        XCTAssertEqual(KRegex("o").replace("foo", KRegex.escapeReplacement("$1\\")), "f$1\\$1\\")
        XCTAssertEqual(KRegex("😀").replace("a😀b😀", "$0$0"), "a😀😀b😀😀") // UTF-16 offsets
    }

    func testOptions() {
        let social = KRegex("Reception|Trivia", options: .ignoreCase)
        XCTAssertTrue(social.containsMatchIn("Evening RECEPTION"))
        XCTAssertTrue(KRegex("é", options: .ignoreCase).containsMatchIn("É")) // Unicode-aware, as in Kotlin
        XCTAssertEqual(KRegex("^x", options: .multiline).findAll("x\nx").count, 2)
        XCTAssertEqual(KRegex("^x").findAll("x\nx").count, 1)
        XCTAssertTrue(KRegex("a.b", options: .dotMatchesAll).matches("a\nb"))
        XCTAssertFalse(KRegex("a.b").matches("a\nb"))
        XCTAssertTrue(KRegex("^Break(?!\\p{L})").containsMatchIn("Break 2"))
        XCTAssertFalse(KRegex("^Break(?!\\p{L})").containsMatchIn("Breakfast"))
        XCTAssertEqual(KRegex.escape("a.b*"), "a\\.b\\*")
    }

    func testSplitKeepsEmptyParts() {
        XCTAssertEqual("a,,b,".split(KRegex(",")), ["a", "", "b", ""])
        XCTAssertEqual("a1b2c".split(KRegex("\\d"), limit: 2), ["a", "b2c"])
        XCTAssertEqual("abc".split(KRegex(",")), ["abc"])
        XCTAssertEqual("x\r\ny".kotlinSplit("\r\n"), ["x", "y"])
        XCTAssertEqual("|a||".kotlinSplit("|"), ["", "a", "", ""])
        XCTAssertEqual("".kotlinSplit("|"), [""])
    }

    func testRegexConstantsCanBeStatic() {
        // Sendable: usable as `static let` under Swift 6.
        enum Patterns { static let digits = KRegex("\\d+") }
        XCTAssertTrue(Patterns.digits.matches("2026"))
    }
}
